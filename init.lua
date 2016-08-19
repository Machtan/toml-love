local path = (...)
local prefix = (path and path.."." or "")

local encode = require(prefix .. "encode")
local decode = require(prefix .. "decode")
local toto = require(prefix .. "toto")

return {
    dumps = encode.dumps,
    loads = decode.loads,
    debug = toto.debug,
}