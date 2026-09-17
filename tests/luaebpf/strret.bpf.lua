-- see strret.sh
local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local action  = require("linux.xdp")
local map     = require("bpf.map")
local xdp     = require("bpf.xdp")

local pack, insert, concat = string.pack, table.insert, table.concat

local HOST    <const> = "example.com" -- the name the ClientHello carries
local SNI     <const> = 115 -- where that name sits in the whole ClientHello
local NAME    <const> = 11  -- and its length
local NAMELEN <const> = 114 -- the byte before it, which is that length
local ETHERLO <const> = 13  -- the ethertype's low byte: six on the ARP frame, zero on every other
local MAXHOST <const> = 64  -- the widest name a read answers, which is the buffer's own width
local PAST    <const> = 200 -- an offset past every packet of the corpus
local DEST    <const> = 0   -- where the ethernet destination sits, and its width
local ADDRESS <const> = 6
local BCAST   <const> = "\xff\xff\xff\xff\xff\xff" -- the ARP frame's destination, and no other's
local MISS    <const> = 9   -- a verdict no seeded value takes
local KEY     <const> = "c64"
local VALUE   <const> = "I4"
local ENTRIES <const> = 8
local IFINDEX <const> = 1
local QUEUE   <const> = 0

local names = map.hash("names", {key = KEY, value = VALUE, entries = ENTRIES})

-- a string on every path, so a caller needs no test
local function readname(p, at)
	local s = p:getstring(at, NAME)
	return s
end

-- the name at 'at' is a string or nothing, the shape examples/common/sni.lua answers in
local function hostname(p, at)
	local n = p:getbyte(at)
	if n < 1 or n > MAXHOST then
		return
	end
	local s = p:getstring(at + 1, n)
	return s
end

-- a string the callee read reaches the caller's own buffer through the pointer it passed
local function found(ctx)
	local p = ctx:packet()
	local name = readname(p, SNI)
	if name == HOST then
		return action.DROP
	end
	return action.PASS
end

-- one frame further: the middle function owns a region for the read and the caller owns another
local function forward(p, at)
	local s = readname(p, at)
	return s
end

local function nested(ctx)
	local p = ctx:packet()
	local name = forward(p, SNI)
	if name == HOST then
		return action.DROP
	end
	return action.PASS
end

local function maybe(ctx)
	local p = ctx:packet()
	local name = hostname(p, ETHERLO)
	if name then
		return action.DROP
	end
	return action.PASS
end

-- the other narrowing, over the same reads, so both forms are proved and not one
local function compared(ctx)
	local p = ctx:packet()
	local name = hostname(p, ETHERLO)
	if name == nil then
		return action.PASS
	end
	return action.DROP
end

-- the read fails inside the callee, and the flag it raises carries the default verdict out
local function aborted(ctx)
	local p = ctx:packet()
	local name = readname(p, PAST)
	if name == HOST then
		return action.DROP
	end
	return action.PASS
end

-- two return sites, each copying the buffer that return read: only the second one's read answers
-- the address the caller compares against, so a copy from the wrong buffer is a different verdict
local function picked(p, at)
	if p:getbyte(ETHERLO) == 0 then
		local a = p:getstring(at, ADDRESS)
		return a
	end
	local b = p:getstring(DEST, ADDRESS)
	return b
end

local function twobuf(ctx)
	local p = ctx:packet()
	local address = picked(p, SNI)
	if address == BCAST then
		return action.DROP
	end
	return action.PASS
end

-- the most arguments a string-returning function may take, since the buffer costs the register
-- after the abort pointer: the read lands in the last one the call has, R5
local function readwide(p, a, b)
	local s = p:getstring(a + b, NAME)
	return s
end

local function widest(ctx)
	local p = ctx:packet()
	local name = readwide(p, SNI - 1, 1)
	if name == HOST then
		return action.DROP
	end
	return action.PASS
end

-- a string every path answers keys the map with no test of its own
local function always(ctx)
	local p = ctx:packet()
	local v = names[readname(p, SNI)]
	if v then
		return v
	end
	return MISS
end

local function keyed(ctx)
	local p = ctx:packet()
	local name = hostname(p, NAMELEN)
	if name then
		local v = names[name]
		if v then
			return v
		end
		return MISS
	end
	return action.PASS
end

-- a default no row returns, so a read that failed is the verdict the file asked for rather than
-- a number the happy path left behind
xdp.program(always, {name = "always", default = action.REDIRECT})
xdp.program(keyed, {name = "keyed", default = action.REDIRECT})

local makers = {found = found, nested = nested, widest = widest, twobuf = twobuf,
	maybe = maybe, compared = compared, aborted = aborted}

local order = {"found", "nested", "widest", "twobuf", "maybe", "compared", "aborted"}

local contexts = {}
for _, name in ipairs(packets.order) do
	contexts[name] = corpus.context(name, "xdp_md",
		{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, packets[name])
end

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, name in ipairs(packets.order) do
		rows:declare(op .. i, makers[op], {default = action.REDIRECT}, contexts[name])
	end
end
rows:close()

-- what the case hands bpftool, from the same spec the programs were compiled against: a key goes
-- on the command line as decimal bytes, and the NUL tail is what makes it the key a read builds
local function rendered(format, value)
	local packed, out = pack(format, value), {}
	for i = 1, #packed do
		insert(out, ("%d"):format(packed:byte(i)))
	end
	return concat(out, " ")
end

local out = assert(io.open("rows.txt", "w"))
out:write("key\tnames\t", rendered(KEY, HOST), "\n")
out:write("value\tnames\t", rendered(VALUE, action.DROP), "\n")
out:write("expect\tseeded\t", action.DROP, "\n")
out:close()

