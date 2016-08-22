-- Created 2016/08/12

local function encode_string(text, append, collapse_newline)
	local quote = '"'
	text = text:gsub("\\", "\\\\")

	-- if the string has any line breaks, make it multiline
	if text:match("^\n(.*)$") then
        text = "\n"..text
		quote = quote:rep(3)
	elseif text:match("\n") then
        text = "\n"..text
		quote = quote:rep(3)
	end

	text = text:gsub("\b", "\\b")
	text = text:gsub("\t", "\\t")
	text = text:gsub("\f", "\\f")
	text = text:gsub("\r", "\\r")
	text = text:gsub('"', '\\"')
	text = text:gsub("\\", "\\\\")
    if collapse_newline then
        text = text:gsub("\n", "\\n")
        quote = '"'
    end
    
    append(quote)
    append(text)
    append(quote)
end

local function is_bare_key(key)
    return (key:match("^[A-Za-z0-9_\\-]*$") ~= nil)
end

local function encode_key(key, scope, append)
    if key == "" then
        error("A key at '"..table.concat(scope, ".").."' is the empty string!")
    end
    if is_bare_key(key) then
        append(key)
    else
        encode_string(key, append, true)
    end
end

local function encode_scope(scope, is_array, append)
    append((is_array and "[[" or "["))
    local parts = #scope
    for i, part in ipairs(scope) do
        encode_key(part, scope, append) -- This will give a bad error
        if i ~= parts then
            append(".")
        end
    end
    append((is_array and "]]\n" or "]\n"))
end

local function toml_type(value)
    local t = type(value)
    if t == "string" or t == "boolean" or t == "number" then
        return t
    elseif t == "table" then
        local is_array = true
        for k, v in pairs(value) do
            if type(k) ~= "number" then
                is_array = false
                break
            end
        end
        if is_array then
            local first = value[1]
            local tt = toml_type(first)
            if tt ~= "table" then
                if tt == "array of tables" then
                    error("You cannot have an array of tables inside an array")
                end
                return "array"
            else
                return "array of tables"
            end
        else
            return "table"
        end
    end
    error("Invalid type given: '"..t.."' ("..tostring(value)..")")
end

local function encode_value(value, append, options, encode_array)
    local t = toml_type(value)
    if t == "string" then
        encode_string(value, append)
    elseif t == "boolean" then
        append(tostring(value))
    elseif t == "number" then
        append(tostring(value))
    elseif t == "array" then
        encode_array(value, append, options)
    else
        error("Invalid simple TOML value: '"..tostring(value).."'")
    end
end

local function encode_array(array, append, options)
    if #array == 0 then
        append("[]")
        return
    end
    append("[")
    if options.expand_arrays then
        append("\n")
        options._indent = options._indent + 2
    end
    local arrtype = toml_type(array[1])
    for i, v in ipairs(array) do
        if toml_type(v) ~= arrtype then
            error("Cannot insert value '"..tostring(v).."' into an array of the type '"..arrtype.."' (TOML arrays must be homogenous)")
        end
        if options.expand_arrays then
            append(string.rep(" ", options._indent))
        end
        encode_value(v, append, options, encode_array)
        if options.expand_arrays then
            append(",\n")
        else
            append(", ")
        end
    end
    if options.expand_arrays then
        options._indent = options._indent - 2
        append(string.rep(" ", options._indent))
    end
    append("]")
end

local function encode_table(tbl, scope, in_array, append, options)
    if #scope ~= 0 then
        encode_scope(scope, in_array, append)
    end
    -- Non-table values first
    for k, v in pairs(tbl) do
        -- Validate all keys
        if type(k) ~= "string" then
            table.insert(scope, k)
            error("The key '"..table.concat(scope, ".").."' is not a string!")
        end
        
        local t = toml_type(v)
        if t ~= "table" and t ~= "array of tables" then
            encode_key(k, scope, append)
            append(" = ")
            encode_value(v, append, options, encode_array)
            append("\n")
        end
    end
    
    -- Insert a newline after the normal values
    append("\n")
    
    -- Then table values
    for k, v in pairs(tbl) do
        local t = toml_type(v)
        if t == "table" then
            table.insert(scope, k) -- push scope
            encode_table(v, scope, false, append, options)
            table.remove(scope) -- pop scope
        elseif t == "array of tables" then
            table.insert(scope, k) -- push scope
            for _, av in ipairs(v) do
                encode_table(av, scope, true, append, options, encode_table)
            end
            table.remove(scope) -- pop scope
        end
    end
end

local OPTION_DEFAULTS = {
    expand_arrays = false,
    _indent = 0,
}
local dumps = function(tbl, options)
    options = options or {}
    for option, default in pairs(OPTION_DEFAULTS) do
        if options[option] == nil then
            options[option] = default
        end
    end
    local t = toml_type(tbl)
    if t ~= "table" then
        error("The top-level TOML value must be a table or an array of tables")
    end
    local list = {}
    local function append(text)
        table.insert(list, text)
    end
    encode_table(tbl, {}, false, append, options)
    return table.concat(list, "")
end

return {
    dumps = dumps
}