-- see host.sh
local xdp    = require("bpf.xdp")
local action = require("linux.xdp")
local probe  = require("luaebpf.probe")
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
assert(read.lines[1] == 13, "the first instruction comes from line " .. read.lines[1])
assert(proto.modes.ADD.mode == "iABC" and proto.modes.ADD.a, "ADD's argument mode is wrong")
assert(read.source:match("host%.bpf%.lua$"), "the source is " .. tostring(read.source))

local function release()
	local file = assert(io.open("/proc/sys/kernel/osrelease", "r"))
	local major, minor = file:read("l"):match("^(%d+)%.(%d+)")
	file:close()
	return tonumber(major), tonumber(minor)
end

-- the probe loads the instruction rather than reading the release, and answers nothing where the
-- load needed a privilege; where it does answer, the release is what it has to agree with
local major, minor = release()
local told = probe.maygoto()
local expected = major > 6 or (major == 6 and minor >= 9)
assert(told == nil or told == expected,
	("the may_goto probe says %s on %d.%d"):format(tostring(told), major, minor))

-- a host that preloaded neither gets the message that names it, not a nil index
local function unhosted(missing, held)
	package.loaded[missing] = nil
	package.loaded["luaebpf"] = nil
	local ok, err = pcall(require("luaebpf").compile, "nothing.bpf.lua")
	assert(not ok and err:match((missing:gsub("%.", "%%."))),
		"a host without " .. missing .. " said: " .. tostring(err))
	package.loaded[missing] = held
end

unhosted("luaebpf.proto", proto)
unhosted("luaebpf.probe", probe)

return xdp.program(function(ctx)
	return action.PASS
end, {name = "host"})

