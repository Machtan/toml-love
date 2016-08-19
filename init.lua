local path = (...)
local prefix = (path and path.."." or "")

local encode = require(prefix .. "encode")
local decode = require(prefix .. "decode")
local toto = require(prefix .. "toto")

local function show_tokens(source)
    for token in toto.tokens(source) do
        local token_type = toto.TokenType:name(token.type)
        local token_text = (token.text ~= nil and (": '"..token.text.."'") or "")
        local text = string.format("%04d: ", token.start)..token_type..token_text
        print(text)
    end
end

local M = {
    dumps = encode.dumps,
    loads = decode.loads,
    debug = toto.debug,
}

M.debug.show_tokens = show_tokens

return M