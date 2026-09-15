-- see the cases under tests/luaebpf: a program file's body declares its rows through here, and
-- writes beside the object what the interpreter answered for each, which the case compares
-- against what the compiled program returns.

local class   = require("class")
local vmlinux = require("luaebpf.vmlinux")
local xdp     = require("bpf.xdp")

local pack = string.pack

local corpus = {}

local rows = class{}

-- what a context's files are named, kept outside the twin so that a kernel struct may have a
-- member of any name
local bases = setmetatable({}, {__mode = "k"})

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

---
-- The stimulus both sides are handed: the bytes `bpftool prog run` builds its context from and
-- the packet, written beside the object as `<name>.ctx` and `<name>.bin`, and the twin the body
-- runs the interpreted function against.
-- @function corpus.context
-- @tparam string name what the case calls this stimulus
-- @tparam string what the context struct `prog run` reads, `xdp_md` or `__sk_buff`
-- @tparam table fields the context fields to fill, by name
-- @tparam string bytes the packet
-- @treturn table the twin, which is `fields` itself
function corpus.context(name, what, fields, bytes)
	write(name .. ".ctx", contextbytes(what, fields))
	write(name .. ".bin", bytes)
	bases[fields] = name
	return fields
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
	local program = xdp.program(fn, opts)
	self.out:write(name, "\t", answer(pcall(fn, ctx or 0)), "\t", program.default, "\t",
		ctx ~= nil and bases[ctx] or "", "\n")
end

function rows:close()
	self.out:close()
end

return corpus

