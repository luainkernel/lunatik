-- see the cases under tests/luaebpf: a program file's body declares its rows through here, and
-- writes beside the object what the interpreter answered for each, which the case compares
-- against what the compiled program returns.

local class   = require("class")
local vmlinux = require("luaebpf.vmlinux")
local xdp     = require("bpf.xdp")

local pack, unpack = string.pack, string.unpack

local corpus = {}

local rows = class{}

-- the packet as the kernel's data object reads it: string.unpack with a native-order format of
-- the exact width, which is the load the emitter lowers each accessor to, rather than a second
-- implementation of its shifts
local packet = class{}

-- what a twin is called and what it carries, kept outside it so that a kernel context struct may
-- have a member of any name
local states = setmetatable({}, {__mode = "k"})

local function read(self, format, at)
	if at < 0 then
		error("offset out of bounds", 0)
	end
	return (unpack(format, self.bytes, at + 1))
end

function packet:getbyte(at) return read(self, "=I1", at) end
function packet:getuint8(at) return read(self, "=I1", at) end
function packet:getint8(at) return read(self, "=i1", at) end
function packet:getuint16(at) return read(self, "=I2", at) end
function packet:getint16(at) return read(self, "=i2", at) end
function packet:getuint32(at) return read(self, "=I4", at) end
function packet:getint32(at) return read(self, "=i4", at) end
function packet:getint64(at) return read(self, "=i8", at) end
function packet:getnumber(at) return read(self, "=i8", at) end

-- luadata_checkbounds wants an offset of its own, a length of at least one byte and both inside
-- the data; the compiled twin has no length of its own, so neither has this one
function packet:getstring(at, len)
	if at < 0 or len < 1 or at + len > #self.bytes then
		error("out of bounds", 0)
	end
	return self.bytes:sub(at + 1, at + len)
end

function packet.__len(self)
	return #self.bytes
end

-- the context the interpreted side is handed: the fields prog run was given, read as a compiled
-- function reads them, and the packet behind :packet()
local context = class{}

function context:packet()
	return states[self].packet
end

local function write(path, bytes)
	local file = assert(io.open(path, "wb"))
	file:write(bytes)
	file:close()
end

-- the context struct bpftool builds its own from: zero everywhere but the fields named here,
-- each at the offset the kernel's own BTF reports, so a wrong offset makes prog run fill a
-- different field than the program reads
local function contextbytes(what, fields)
	local layout = vmlinux.layout(what)
	local bytes = ("\0"):rep(layout.size)
	for _, field in ipairs(layout.fields) do
		local value = fields[field.name]
		if value ~= nil then
			bytes = bytes:sub(1, field.offset) .. pack("=I" .. field.size, value)
				.. bytes:sub(field.offset + field.size + 1)
		end
	end
	return bytes
end

-- the stimulus both sides are handed: the bytes bpftool prog run builds its context from and the
-- packet, written beside the object as <name>.ctx and <name>.bin, and the twin the body runs the
-- interpreted function against
function corpus.context(name, what, fields, bytes)
	if what == "xdp_md" then
		-- bpf_prog_test_run_xdp sizes the packet from ctx_in.data_end, empty when it is zero (test_run.c)
		fields.data_end = #bytes
	end
	write(name .. ".ctx", contextbytes(what, fields))
	write(name .. ".bin", bytes)
	if what == "__sk_buff" then
		-- convert___skb_to_skb refuses a non-zero __sk_buff.len and sizes skb->len from the packet
		fields.len = #bytes
	end
	local twin = context:new(fields)
	states[twin] = {name = name, packet = packet:new{bytes = bytes}}
	return twin
end

local function answer(ok, value)
	if not ok then
		return "raises"
	end
	if type(value) == "boolean" then
		return value and "1" or "0"
	end
	return tostring(value & 0xffffffff)
end

function corpus.new(path)
	return rows:new{out = assert(io.open(path or "oracle.txt", "w"))}
end

function rows:declare(name, fn, opts, ctx)
	opts = opts or {}
	opts.name = name
	local program = (opts.program or xdp.program)(fn, opts)
	self.out:write(name, "\t", answer(pcall(fn, ctx or 0)), "\t", program.default, "\t",
		ctx ~= nil and states[ctx].name or "", "\n")
end

function rows:close()
	self.out:close()
end

return corpus

