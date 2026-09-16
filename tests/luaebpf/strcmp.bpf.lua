-- see strcmp.sh
local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local action  = require("linux.xdp")

local unpack = string.unpack

local HOST    <const> = "example.com"
local SNI     <const> = 115 -- where that name sits in the whole ClientHello
local NAME    <const> = 11  -- and how long it is
local SHORT   <const> = 7   -- a read the constant is longer than
local TYPEHI  <const> = 12  -- the ethertype's high byte, 8 on every packet of the corpus
local BYTES   <const> = 8   -- and so a bound the constant does not fit in
local AT      <const> = 14  -- the first byte past the ethernet header
local NULS    <const> = 8
local WORD    <const> = 8   -- what a comparison reads at a time
local IFINDEX <const> = 1
local QUEUE   <const> = 0

local FRAME <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x08\x00"

local function equal(ctx)
	local p = ctx:packet()
	local s = p:getstring(SNI, NAME)
	if s == HOST then
		return action.DROP
	end
	return action.PASS
end

-- the constant as a constant of the bytecode rather than a value the body computed
local function literal(ctx)
	local p = ctx:packet()
	local s = p:getstring(SNI, NAME)
	if s == "example.com" then
		return action.DROP
	end
	return action.PASS
end

-- a constant that is a prefix of the read, and a read that is a prefix of the constant
local function prefix(ctx)
	local p = ctx:packet()
	local s = p:getstring(SNI, NAME)
	if s == "example" then
		return action.DROP
	end
	return action.PASS
end

local function shorter(ctx)
	local p = ctx:packet()
	local s = p:getstring(SNI, SHORT)
	if s == HOST then
		return action.DROP
	end
	return action.PASS
end

local function empty(ctx)
	local p = ctx:packet()
	local s = p:getstring(SNI, NAME)
	if s == "" then
		return action.DROP
	end
	return action.PASS
end

local function differs(ctx)
	local p = ctx:packet()
	local s = p:getstring(SNI, NAME)
	if s ~= HOST then
		return action.PASS
	end
	return action.DROP
end

local function matches(p)
	local s = p:getstring(SNI, NAME)
	if s == HOST then
		return 1
	end
	return 0
end

local function called(ctx)
	local p = ctx:packet()
	local hit = matches(p)
	if hit == 1 then
		return action.DROP
	end
	return action.PASS
end

-- a constant longer than the bound the program proved: never equal, and settled while compiling
local function beyond(ctx)
	local p = ctx:packet()
	local n = p:getbyte(TYPEHI)
	if n > BYTES then
		return action.ABORTED
	end
	local s = p:getstring(AT, n)
	if s == HOST then
		return action.DROP
	end
	return action.PASS
end

local function padded(ctx)
	local p = ctx:packet()
	local s = p:getstring(AT, NAME)
	if s == HOST then
		return action.DROP
	end
	return action.PASS
end

-- the read that proves the length is carried: the constant followed by NULs is not the constant,
-- where a comparison of the bytes alone would say it is
local function nultail(ctx)
	local p = ctx:packet()
	local s = p:getstring(AT, NAME + 2)
	if s == HOST then
		return action.DROP
	end
	return action.PASS
end

local makers = {equal = equal, literal = literal, prefix = prefix, shorter = shorter,
	empty = empty, differs = differs, called = called, beyond = beyond}

local order = {"equal", "literal", "prefix", "shorter", "empty", "differs", "called", "beyond"}

local contexts = {}
for _, name in ipairs(packets.order) do
	contexts[name] = corpus.context(name, "xdp_md",
		{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, packets[name])
end
local tail = corpus.context("tail", "xdp_md",
	{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, FRAME .. HOST .. ("\0"):rep(NULS))

local rows = corpus.new()
for _, op in ipairs(order) do
	for i, name in ipairs(packets.order) do
		rows:declare(op .. i, makers[op], {default = action.REDIRECT}, contexts[name])
	end
end
rows:declare("padded", padded, {default = action.REDIRECT}, tail)
rows:declare("nultail", nultail, {default = action.REDIRECT}, tail)
rows:close()

-- the constant's first word, as the emitter loads it to compare against: what says whether a
-- program carries the comparison at all
local out = assert(io.open("constant.txt", "w"))
out:write(("%016x"):format(unpack("=i8", HOST .. ("\0"):rep(WORD))), "\n")
out:close()

