-- see getstring.sh
local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local action  = require("linux.xdp")
local verdict = require("linux.tc")
local tc      = require("bpf.tc")

local WIDTH   <const> = 64  -- the buffer's width, which is what a program tests its length against
local ETHER   <const> = 14  -- the first byte past the ethernet header
local TYPEHI  <const> = 12  -- the ethertype's high byte, 8 on every packet of the corpus
local BYTES   <const> = 8   -- and so the length every row reads from there
local SNI     <const> = 115 -- the host name in the whole ClientHello
local NAME    <const> = 11  -- and its length
local DEEP    <const> = 110 -- inside the whole ClientHello's SNI, past the truncated one
local SPAN    <const> = 12
local TAIL    <const> = 4   -- an offset eight bytes run off the end of every packet from
local BACK    <const> = 20  -- and one the same byte computes a negative offset with
local IFINDEX <const> = 1
local QUEUE   <const> = 0

-- the length the program proved itself, by testing the byte it read against the buffer's width
local function bounded(ctx)
	local p = ctx:packet()
	local n = p:getbyte(TYPEHI)
	if n > WIDTH then
		return action.ABORTED
	end
	local s = p:getstring(ETHER, n)
	return action.DROP
end

local function constant(ctx)
	local p = ctx:packet()
	local s = p:getstring(ETHER, BYTES)
	return action.DROP
end

-- luadata_checkbounds raises below one byte, and so does ARG_CONST_SIZE
local function zero(ctx)
	local p = ctx:packet()
	local n = p:getbyte(TYPEHI) - BYTES
	if n > WIDTH then
		return action.ABORTED
	end
	local s = p:getstring(ETHER, n)
	return action.DROP
end

local function negative(ctx)
	local p = ctx:packet()
	local n = p:getbyte(TYPEHI) - BYTES - 1
	if n > WIDTH then
		return action.ABORTED
	end
	local s = p:getstring(ETHER, n)
	return action.DROP
end

local function past(ctx)
	local p = ctx:packet()
	local at = #p - TAIL
	local s = p:getstring(at, BYTES)
	return action.DROP
end

local function deep(ctx)
	local p = ctx:packet()
	local s = p:getstring(DEEP, SPAN)
	return action.PASS
end

local function negoffset(ctx)
	local p = ctx:packet()
	local at = p:getbyte(TYPEHI) - BACK
	local s = p:getstring(at, BYTES)
	return action.DROP
end

local function reader(p)
	local s = p:getstring(DEEP, SPAN)
	return SPAN
end

-- a read that fails inside a called function reaches the caller's default verdict through the
-- flag the callee raises in its frame
local function called(ctx)
	local p = ctx:packet()
	local n = reader(p)
	return action.TX
end

-- the same read in a TC program, which takes the other helper
local function sched(skb)
	local p = skb:packet()
	local s = p:getstring(SNI, NAME)
	return verdict.ACT_OK
end

local makers = {bounded = bounded, constant = constant, zero = zero, negative = negative,
	past = past, deep = deep, negoffset = negoffset, called = called}

local order = {"bounded", "constant", "zero", "negative", "past", "deep", "negoffset", "called"}

local contexts = {}
for _, name in ipairs(packets.order) do
	contexts[name] = corpus.context(name, "xdp_md",
		{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, packets[name])
end
local skbtls = corpus.context("skbtls", "__sk_buff", {ingress_ifindex = IFINDEX}, packets.tls)

-- every row runs under a default no row returns, so a read that took the failure path is the
-- verdict the file asked for rather than a number the happy path left behind
local rows = corpus.new()
for _, op in ipairs(order) do
	for i, name in ipairs(packets.order) do
		rows:declare(op .. i, makers[op], {default = action.REDIRECT}, contexts[name])
	end
end
rows:declare("sched", sched, {program = tc.program, default = verdict.ACT_SHOT}, skbtls)
rows:close()

