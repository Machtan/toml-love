local ffi = require("ffi")

ffi.cdef[[
typedef struct {} Tokens;
typedef struct {} TokenError;
int32_t toto_tokenizer_new(const char* source, Tokens** tokenizer);
int32_t toto_tokenizer_next(Tokens* tokenizer, int32_t* token_type,
    int32_t* has_text, const char** text, size_t* len, size_t* start, 
    int32_t* has_error, TokenError** error);
int32_t toto_tokenizer_destroy(Tokens* tokenizer);
int32_t toto_error_explain(TokenError* error, const char* source);
int32_t toto_error_destroy(TokenError* error);
int32_t toto_debug_get_position(const char* source, size_t byte_offset, 
    size_t* col, size_t* row);
int32_t toto_debug_show_unclosed(const char* source, size_t start);
int32_t toto_debug_show_invalid_character(const char* source, size_t pos);
int32_t toto_debug_show_invalid_part(const char* source, size_t start, size_t pos);
]]

-- global defaults to true
local function ffi_load_without_closing(path, global)
    ffi.cdef([[
        void *dlopen(const char *, int);
    ]])
    
    -- LuaJIT unloads each loaded library with `dlclose` when the
    -- handle is garbage-collected, but if the library has set
    -- global state (e.g. thread-local finalizers), things can get
    -- ugly, since this state can still be used, but no longer exists.
    --
    -- By calling `dlopen` with the same path, we increment its
    -- reference count, meaning it won't be unloaded with the automatic
    -- call to `dlclose`, but would require another. This means the
    -- library will b loaded for the entirety of the program.
    ffi.C.dlopen(path, 1)
    
    return ffi.load(path, global)
end

local info = debug.getinfo(1)
local script_dir = info.short_src:match('^(.*)/.*$')
local PATH = script_dir .. "/libs/libtoto.dylib"
local toto = ffi_load_without_closing(PATH)

local _debug = {}

function _debug.get_position(source, byte_offset)
    local col = ffi.new("size_t[1]")
    local row = ffi.new("size_t[1]")
    toto.toto_debug_get_position(source, byte_offset, col, row)
    return tonumber(col[0]), tonumber(row[0])
end

function _debug.show_unclosed(source, start)
    toto.toto_debug_show_unclosed(source, start)
end

function _debug.show_invalid_character(source, pos)
    toto.toto_debug_show_invalid_character(source, pos)
end

function _debug.show_invalid_part(source, start, pos)
    toto.toto_debug_show_invalid_part(source, start, pos)
end

local TokenType = {
    Whitespace = 1,
    SingleBracketOpen = 2,
    DoubleBracketOpen = 3,
    SingleBracketClose = 4,
    DoubleBracketClose = 5,
    CurlyOpen = 6,
    CurlyClose = 7,
    Comment = 8,
    Equals = 9,
    Comma = 10,
    Dot = 11,
    Newline = 12,
    Key = 13,
    String = 14,
    MultilineString = 15,
    Literal = 16,
    MultilineLiteral = 17,
    Datetime = 18,
    Int = 19,
    Float = 20,
    True = 21,
    False = 22,
}

function TokenType:name(value)
    for k, v in pairs(self) do
        if v == value then
            return k
        end
    end
    error("Invalid TokenType enum value")
end

local Tokens = {}

function Tokens:new(source)
    if type(source) ~= "string" then
        error("The source must be a string, not '"..type(source).."'")
    end
    local ptr = ffi.new("Tokens *[1]")
    local res = toto.toto_tokenizer_new(source, ptr)
    if res ~= 0 then
        if res == -1 then
            error("Invalid UTF8")
        elseif res == -2 then
            error("The text is NULL")
        else
            error("Unknown error")
        end
    end
    self.__index = self
    return setmetatable({
        raw = ptr[0],
        freed = false,
        source = source,
        finished = false,
    }, self)
end

function Tokens:next()
    if self.finished then
        return nil
    end
    local token_type = ffi.new("int32_t[1]")
    local has_text = ffi.new("int32_t[1]")
    local text = ffi.new("const char*[1]")
    local len = ffi.new("size_t[1]")
    local start = ffi.new("size_t[1]")
    local has_error = ffi.new("int32_t[1]")
    local errptr = ffi.new("TokenError*[1]")
    local res = toto.toto_tokenizer_next(self.raw, token_type, has_text, text, 
        len, start, has_error, errptr)
    if res == 0 then
        local token_text
        if has_text[0] ~= 0 then
            token_text = ffi.string(text[0], len[0])
        else
            token_text = nil
        end
        return {
            type = tonumber(token_type[0]), 
            text = token_text,
            start = tonumber(start[0]),
        }
    else
        self.finished = true
        self:destroy()
        if res == -2 then
            error("The tokenizer was null")
        elseif has_error[0] ~= 0 then
            toto.toto_error_explain(errptr[0], self.source)
            toto.toto_error_destroy(errptr[0])
            error("Tokens error")
        else
            return nil
        end
    end
end

function Tokens:iter()
    return function()
        return self:next()
    end
end

function Tokens:destroy()
    if not self.freed then
        toto.toto_tokenizer_destroy(self.raw)
        self.freed = true
        self.finished = true
    else
        error("Tokens freed twice!")
    end
end

function tokens(text)
    local tok = Tokens:new(text)
    return function()
        return tok:next()
    end
end

function stripped_tokens(text)
    local tok = Tokens:new(text)
    return function()
        local token = tok:next()
        while token ~= nil do
            if token.type == TokenType.Whitespace 
            or token.type == TokenType.Comment then
                token = tok:next()
            else
                return token
            end
        end
    end
end

return {
    Tokens = Tokens,
    tokens = tokens,
    stripped_tokens = stripped_tokens,
    TokenType = TokenType,
    debug = _debug,
}