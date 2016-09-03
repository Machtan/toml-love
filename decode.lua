local local_path = (...):match('(.-)[^%.]+$')
local prefix = (local_path and local_path or "")
local toto = require(prefix .. "toto")
local TokenType = toto.TokenType

local function unicode_value(text)
    if text:len() == 4 then
        return "?"
    elseif text:len() == 8 then
        return "?"
    else
        error("Invalid unicode scalar")
    end
end

local SHORT_UNICODE_PATTERN = "\\u("..(string.rep("[0-9a-fA-F]", 4))..")"
local LONG_UNICODE_PATTERN = "\\U("..(string.rep("[0-9a-fA-F]", 8))..")"
local function clean_string(text)
    text = text:gsub("\\\\", "\\")
    text = text:gsub("\\\"", "\"")
    text = text:gsub("\\n", "\n")
    text = text:gsub("\\t", "\t")
    text = text:gsub("\\b", "\b")
    text = text:gsub("\\f", "\f")
    text = text:gsub("\\r", "\r")
    text = text:gsub("\\(%s+)", "")
    text = text:gsub(SHORT_UNICODE_PATTERN, unicode_value)
    text = text:gsub(LONG_UNICODE_PATTERN, unicode_value)
    return text
end

local function read_one(tokens, source)
    local token = tokens()
    if token == nil then
        raise_err_invalid_pos("%d:%d: Expected one more token:",
            source, source:len())
    end
    return token
end

local function raise_err_unclosed(message, source, start)
    local col, row = toto.debug.get_position(source, start)
    local message = string.format(message, col, row)
    print(message)
    toto.debug.show_unclosed(source, start)
    error(message)
end

local function raise_err_invalid_part(message, source, start, pos)
    local col, row = toto.debug.get_position(source, start)
    local message = string.format(message, col, row)
    print(message)
    toto.debug.show_invalid_part(source, start, pos)
    error(message)
end

local function raise_err_invalid_pos(message, source, pos)
    local col, row = toto.debug.get_position(source, pos)
    local message = string.format(message, col, row)
    print(message)
    toto.debug.show_invalid_character(source, pos)
    error(message)
end

local function read_array(tokens, source, interpret_value, read_value, read_table)
    local expect_value = true
    local array = {}
    local start
    for token in tokens do
        if start == nil then
            start = token.start
        end
        --print("Array Token: "..TokenType:name(token.type))
        if token.type ~= TokenType.Newline then
            if token.type == TokenType.SingleBracketClose then
                return array
            elseif token.type == TokenType.Comma then
                if expect_value then
                    raise_err_invalid_pos("%d:%d: Expected key after comma:",
                        source, token.start)
                end
                expect_value = true
            else
                local value = interpret_value(token, tokens, source, read_value, read_table)
                table.insert(array, value)
                expect_value = false
            end
        end
    end
    if start == nil then -- This is the last token
        start = source:len() - 1
    end
    raise_err_unclosed("%d:%d: Unclosed array:", source, start)
end

local function interpret_value(token, tokens, source, read_value, read_table)
    if token.type == TokenType.String then
        return clean_string(token.text)
    
    elseif token.type == TokenType.MultilineString then
        return clean_string(token.text)
    
    elseif token.type == TokenType.Literal then
        return token.text
    
    elseif token.type == TokenType.MultilineLiteral then
        return token.text
    
    elseif token.type == TokenType.Datetime then
        return token.text
    
    elseif token.type == TokenType.Int then
        return tonumber(token.text)
    
    elseif token.type == TokenType.Float then
        return tonumber(token.text)
    
    elseif token.type == TokenType.True then
        return true
    
    elseif token.type == TokenType.False then
        return false
    
    elseif token.type == TokenType.SingleBracketOpen then
        return read_array(tokens, source, interpret_value, read_value, read_table)
    
    elseif token.type == TokenType.CurlyOpen then
        return read_table(tokens, source, true)
    end
end

local function read_value(tokens, source, read_table)
    local first = read_one(tokens, source)
    return interpret_value(first, tokens, source, read_value, read_table)
end

local function read_newline(tokens, source)
    local start
    for token in tokens do
        if start == nil then
            start = token.start
        end
        if token.type == TokenType.Newline then
            return
        else
            raise_err_invalid_pos("%d:%d: Expected newline:",
                source, start, token.start)
        end
    end
end

local function read_entry(tokens, source, inline, read_table)
    local eq = read_one(tokens, source)
    if eq.type ~= TokenType.Equals then
        raise_err_invalid_part("%d:%d: Expected equals sign:",
            source, start, cur_token.start)
    end
    local value = read_value(tokens, source, read_table)
    if not inline then
        read_newline(tokens, source)
    end
    return value
end

local function read_scope(tokens, source, is_array_of_tables)
    local scope = {}
    local expect_key = true
    local start
    
    local cur_token
    local function insert(key)
        if not expect_key then
            raise_err_invalid_part("%d:%d: Expected scope separator:",
                source, start, cur_token.start)
        end
        table.insert(scope, key)
        expect_key = false
    end
    
    for token in tokens do
        cur_token = token
        if start == nil then
            start = token.start
        end
        if token.type == TokenType.Key then
            insert(token.text)
        
        elseif token.type == TokenType.String then
            insert(clean_string(token.text))
        
        elseif token.type == TokenType.MultilineString then
            insert(clean_string(token.text))
        
        elseif token.type == TokenType.Literal then
            insert(token.text)
        
        elseif token.type == TokenType.MultilineLiteral then
            insert(token.text)
        
        elseif token.type == TokenType.Dot then
            if expect_key then
                if start == nil then
                    start = source:len()
                end
                raise_err_invalid_part("%d:%d: Expected scope key:",
                    source, start, token.start)
            end
            expect_key = true
        
        elseif token.type == TokenType.Whitespace then
        
        elseif token.type == TokenType.SingleBracketClose and not is_array_of_tables then
            if expect_key then
                raise_err_invalid_part("%d:%d: Expected key in scope:", source, start, token.start)
            end
            read_newline(tokens, source)
            return scope
        
        elseif token.type == TokenType.DoubleBracketClose and is_array_of_tables then
            if expect_key then
                raise_err_invalid_part("%d:%d: Expected key in scope:", source, start, token.start)
            end
            read_newline(tokens, source)
            return scope
        else
            raise_err_invalid_part("%d:%d: Unexpected item in scope:",
                source, start, token.start)
        end
    end
end

local function read_table(tokens, source, inline)
    local top_table = {}
    local cur_table = top_table
    local expect_key = true
    local start
    local cur_token
    
    local function insert(key, cur_table)
        if not expect_key then
            raise_err_invalid_pos("%d:%d: Expected comma before key:",
                source, cur_token.start or start)
        end
        local value = read_entry(tokens, source, inline, read_table)
        if cur_table[key] ~= nil then
            raise_err_invalid_pos("%d:%d: Key '"..key.."' defined a second time:",
                source, cur_token.start)
        end
        cur_table[key] = value
        if inline then
            expect_key = false
        end
    end
    
    for token in tokens do
        cur_token = token
        if start == nil then
            start = token.start
        end
        local ty = TokenType:name(token.type)
        local text = (token.text or "")
        --print(string.format("%03d: "..ty..": '"..text.."'", i))
        
        -- Check for scopes
        local token_checked = false
        if not inline then
            if token.type == TokenType.SingleBracketOpen then
                cur_table = top_table
                local scope = read_scope(tokens, source, false)
                --print("Scope: "..table.concat(scope, "."))
                for _, part in ipairs(scope) do
                    local existing = cur_table[part]
                    if existing ~= nil then
                        if type(existing) ~= "table" then
                            raise_err_invalid_pos("%d:%d: Scope path member already in use:",
                                source, token.start)
                        end
                        if #existing > 0 then
                            --print(string.format("'%s' is an array! (len %d)", part, #existing))
                            cur_table = existing[#existing]
                        else
                            cur_table = existing
                        end
                    else
                        local new_table = {}
                        cur_table[part] = new_table
                        cur_table = new_table
                    end
                end
                token_checked = true
                
            elseif token.type == TokenType.DoubleBracketOpen then
                cur_table = top_table
                local scope = read_scope(tokens, source, true)
                --print("Scope: "..table.concat(scope, "."))
                for i, part in ipairs(scope) do
                    local is_last = (i == #scope)
                    local existing = cur_table[part]
                    if not is_last then
                        if existing ~= nil then
                            if type(existing) ~= "table" then
                                raise_err_invalid_pos("%d:%d: Scope path member already in use:",
                                    source, token.start)
                            end
                            if #existing > 0 then
                                cur_table = existing[#existing]
                            else
                                cur_table = existing
                            end
                        else
                            local new_table = {}
                            cur_table[part] = new_table
                            cur_table = new_table
                        end
                    else
                        if existing ~= nil then
                            if type(existing) ~= "table" then
                                raise_err_invalid_pos("%d:%d: Scope path member already in use:",
                                    source, token.start)
                            end
                            local element = {}
                            table.insert(existing, element)
                            cur_table = element
                        else
                            local arr = {}
                            cur_table[part] = arr
                            local first_element = {}
                            arr[1] = first_element
                            cur_table = first_element
                        end
                    end
                end
                token_checked = true
                
            elseif token.type == TokenType.Newline then
                token_checked = true
            end
        
        -- Otherwise, check for the end of the inline table
        else
            if token.type == TokenType.CurlyClose then
                return top_table
            
            elseif token.type == TokenType.Comma then
                if expect_key then
                    raise_err_invalid_pos("%d:%d: Expected key after comma:",
                        source, token.start)
                end
                expect_key = true
                token_checked = true
            end
        end
        
        -- Check for key/value entries
        if token.type == TokenType.Key then
            insert(token.text, cur_table)
        
        elseif token.type == TokenType.String then
            insert(clean_string(token.text), cur_table)
        
        elseif token.type == TokenType.MultilineString then
            insert(clean_string(token.text), cur_table)
        
        elseif token.type == TokenType.Literal then
            insert(token.text, cur_table)
        
        elseif token.type == TokenType.MultilineLiteral then
            insert(token.text, cur_table)
        
        elseif not token_checked then
            raise_err_invalid_pos(
                "%d:%d: Invalid table token: '"..TokenType:name(token.type).."'",
                source, token.start
            )
        end
    end
    if inline then
        if start == nil then
            start = source:len() - 1
        end
        raise_err_unclosed("%d:%d: Unclosed inline table:", source, start)
    end
    return top_table
end

local function loads(source)
    local tokens = toto.stripped_tokens(source)
    return read_table(tokens, source, false)
end

return {
    loads = loads,
}