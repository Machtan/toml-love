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

local function read_one(tokens)
    local token = tokens()
    if token == nil then
        error("No more tokens")
    end
    return token
end

local function read_array(tokens, interpret_value, read_value, read_table)
    local expect_value = true
    local array = {}
    for token in tokens do
        --print("Array Token: "..TokenType:name(token.type))
        if token.type ~= TokenType.Newline then
            if token.type == TokenType.SingleBracketClose then
                return array
            elseif token.type == TokenType.Comma then
                if expect_value then
                    error("Found comma after comma!")
                end
                expect_value = true
            else
                local value = interpret_value(token, tokens, read_value, read_table)
                table.insert(array, value)
                expect_value = false
            end
        end
    end
    local dalgi = require("dalgi")
    print("Array:")
    dalgi.print(array)
    error("Unclosed array! (Unreachable)")
end

local function interpret_value(token, tokens, read_value, read_table)
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
        return read_array(tokens, interpret_value, read_value, read_table)
    
    elseif token.type == TokenType.CurlyOpen then
        return read_table(tokens, true)
    end
end

local function read_value(tokens, read_table)
    local first = read_one(tokens)
    return interpret_value(first, tokens, read_value, read_table)
end

local function read_newline(tokens)
    for token in tokens do
        if token.type == TokenType.Newline then
            return
        else
            error("Found unexpected token: '"..TokenType:name(token.type).."'")
        end
    end
end

local function read_entry(tokens, inline, read_table)
    local eq = tokens()
    if eq.type ~= TokenType.Equals then
        error("No equals sign found")
    end
    local value = read_value(tokens, read_table)
    if not inline then
        read_newline(tokens)
    end
    return value
end

local function read_scope(tokens, is_array_of_tables)
    local scope = {}
    local expect_key = true
    
    local function insert(key)
        if not expect_key then
            error("Found key in scope without separator")
        end
        table.insert(scope, key)
        expect_key = false
    end
    
    for token in tokens do
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
                error("Found a dot not after a key")
            end
            expect_key = true
        
        elseif token.type == TokenType.Whitespace then
        
        elseif token.type == TokenType.SingleBracketClose and not is_array_of_tables then
            read_newline(tokens)
            return scope
        
        elseif token.type == TokenType.DoubleBracketClose and is_array_of_tables then
            read_newline(tokens)
            return scope
        else
            error("Unexpected item in scope: '"..TokenType:name(token.type).."'")
        end
    end
end

local function read_table(tokens, inline)
    local top_table = {}
    local cur_table = top_table
    local expect_key = true
    
    local function insert(key)
        if not expect_key then
            error("Expected comma before key in inline table")
        end
        local value = read_entry(tokens, inline, read_table)
        if cur_table[key] ~= nil then -- TODO better error from clib
            error("Key '"..key.."' defined twice!")
        end
        cur_table[key] = value
        if inline then
            expect_key = false
        end
        --print(key.." = "..dalgi.prettify(value))
    end
    
    for token in tokens do
        local ty = TokenType:name(token.type)
        local text = (token.text or "")
        --print(string.format("%03d: "..ty..": '"..text.."'", i))
        
        -- Check for scopes
        local token_checked = false
        if not inline then
            if token.type == TokenType.SingleBracketOpen then
                cur_table = top_table
                local scope = read_scope(tokens, false)
                --print("Scope: "..dalgi.prettify(scope))
                for _, part in ipairs(scope) do
                    local existing = cur_table[part]
                    if existing ~= nil then
                        if type(existing) ~= "table" then
                            error("The key '' is already in use") -- TODO
                        end
                    else
                        local new_table = {}
                        cur_table[part] = new_table
                        cur_table = new_table
                    end
                end
                token_checked = true
                
            elseif token.type == DoubleBracketOpen then
                cur_table = top_table
                local scope = read_scope(tokens, true)
                --print("Scope: "..dalgi.prettify(scope))
                for _, part in ipairs(scope) do
                    local existing = cur_table[part]
                    if existing ~= nil then
                        if type(existing) ~= "table" then
                            error("The key '' is already in use") -- TODO
                        end
                    else
                        local new_table = {}
                        cur_table[part] = new_table
                        cur_table = new_table
                    end
                end
                local new_element = {}
                table.insert(cur_table, new_element)
                cur_table = new_element
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
                    error("Expected key, not comma")
                end
                expect_key = true
                token_checked = true
            end
        end
        
        -- Check for key/value entries
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
        
        elseif not token_checked then
            error("Invalid table token: '"..TokenType:name(token.type).."'")
        end
    end
    return top_table
end

local function loads(text)
    local tokens = toto.stripped_tokens(text)
    return read_table(tokens, false)
end

return {
    loads = loads,
}