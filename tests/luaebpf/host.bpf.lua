-- see host.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")
local proto  = require("luaebpf.proto")

local string, io, debug = require("string"), require("io"), require("debug")
assert(string.format("%d", 7) == "7", "string is missing from the host state")
assert(io.open ~= nil and debug.getupvalue ~= nil, "io or debug is missing from the host state")
assert(action.PASS == 2, "linux.xdp does not carry the kernel's verdicts")

local function subject(a, b)
	return a + b
end

local read = proto.read(subject)
assert(read.numparams == 2, "numparams is " .. read.numparams)
assert(read.maxstacksize >= 2, "maxstacksize is " .. read.maxstacksize)
assert(read.isvararg == false, "subject is not a vararg function")
assert(read.code[1].op == proto.opcodes.ADD, "the first opcode is not ADD")
assert(read.lines[1] == 12, "the first instruction comes from line " .. read.lines[1])
assert(proto.modes.ADD.mode == "iABC" and proto.modes.ADD.a, "ADD's argument mode is wrong")
assert(read.source:match("host%.bpf%.lua$"), "the source is " .. tostring(read.source))

-- a host that preloaded no accessor gets the message that names it, not a nil index
package.loaded["luaebpf.proto"] = nil
package.loaded["luaebpf"] = nil
local unhosted = require("luaebpf")
local ok, err = pcall(unhosted.compile, "nothing.bpf.lua")
assert(not ok and err:match("luaebpf%.proto"), "unhosted compile said: " .. tostring(err))
package.loaded["luaebpf.proto"] = proto

return xdp.program(function(ctx)
	return action.PASS
end, {name = "host"})

