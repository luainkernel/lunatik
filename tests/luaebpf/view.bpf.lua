--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the view case (see view.sh).

local corpus  = require("tests.luaebpf.corpus")
local packets = require("tests.luaebpf.packets")
local struct  = require("struct")
local vmlinux = require("bpf.vmlinux")
local action  = require("linux.xdp").action
local tc      = require("linux.tc").action
local eth     = require("linux.eth")

local WORD <const> = 4 -- bytes in a unit of iphdr's ihl
local AT   <const> = 6 -- the source address, whose first byte has its high bit set
local SYN  <const> = 58 -- bytes of the corpus's SYN, which two packets are longer than

local ethhdr = struct(vmlinux.layout("ethhdr"))
local iphdr  = struct(vmlinux.layout("iphdr"))
local tcphdr = struct(vmlinux.layout("tcphdr"))

-- the signs and the width the kernel's headers give no field of, over the source address: a byte, a
-- signed big-endian field, a signed native one and a signed bitfield, each with its high bit set
local signed = struct{size = 8, fields = {
	{name = "i8", offset = 0, size = 1, signed = true},
	{name = "bei16", offset = 1, size = 2, signed = true, bigendian = true},
	{name = "i16", offset = 4, size = 2, signed = true},
}, bitfields = {
	{name = "nibble", offset = 3, size = 1, signed = true, shift = 4, mask = 15},
}}
local wide = struct{size = 8, fields = {{name = "be64", offset = 0, size = 8, signed = false, bigendian = true}}}

-- each read a function of the packet, which the program calls with it: the view is made and read in
-- the callee's frame, past the packet it was handed
local reads = {}

function reads.proto(p) local h = ethhdr:view(p, 0) return h.h_proto end
function reads.version(p) local ip = iphdr:view(p, eth.HLEN) return ip.version end
function reads.ihl(p) local ip = iphdr:view(p, eth.HLEN) return ip.ihl end
function reads.ttl(p) local ip = iphdr:view(p, eth.HLEN) return ip.ttl end
function reads.totlen(p) local ip = iphdr:view(p, eth.HLEN) return ip.tot_len end
function reads.check(p) local ip = iphdr:view(p, eth.HLEN) return ip.check end
function reads.i8(p) local s = signed:view(p, AT) return s.i8 end
function reads.bei16(p) local s = signed:view(p, AT) return s.bei16 end
function reads.i16(p) local s = signed:view(p, AT) return s.i16 end
function reads.nibble(p) local s = signed:view(p, AT) return s.nibble end
function reads.be64(p) local w = wide:view(p, AT) return w.be64 end

-- where the TCP header starts, past the IPv4 one, by its ihl
local function tcpat(p)
	local ip = iphdr:view(p, eth.HLEN)
	local at = eth.HLEN + ip.ihl * WORD
	return at
end

function reads.dest(p) local at = tcpat(p) local h = tcphdr:view(p, at) return h.dest end
function reads.seq(p) local at = tcpat(p) local h = tcphdr:view(p, at) return h.seq end
function reads.doff(p) local at = tcpat(p) local h = tcphdr:view(p, at) return h.doff end
function reads.psh(p) local at = tcpat(p) local h = tcphdr:view(p, at) return h.psh end

local order = {"proto", "version", "ihl", "ttl", "totlen", "check", "i8", "bei16", "i16", "nibble", "be64",
	"dest", "seq", "doff", "psh"}

local function xdp(read)
	return function(keep)
		return function(ctx) local p = ctx:packet() local v = read(p) keep(v) end
	end
end

local function sched(read)
	return function(keep)
		return function(skb) local p = skb:data() local v = read(p) keep(v) end
	end
end

-- a view made and read in the program's own frame, through the context, where a field read past
-- the packet stops the program after what an earlier field kept
local makers = {}

function makers.inline(keep)
	return function(ctx)
		local p = ctx:packet()
		local ip = iphdr:view(p, eth.HLEN)
		local h = tcphdr:view(p, eth.HLEN + ip.ihl * WORD)
		keep(h.dest)
		local v = h.doff
		keep(v)
	end
end

function makers.skbinline(keep)
	return function(skb)
		local p = skb:data()
		local ip = iphdr:view(p, eth.HLEN)
		local h = tcphdr:view(p, eth.HLEN + ip.ihl * WORD)
		keep(h.dest)
		local v = h.doff
		keep(v)
	end
end

-- a view each arm of a branch makes of the one struct, at an offset of its own, read where the arms meet
function makers.joined(keep)
	return function(ctx)
		local p = ctx:packet()
		local ip
		if #p > SYN then
			ip = iphdr:view(p, eth.HLEN)
		else
			ip = iphdr:view(p, 0)
		end
		keep(ip.ttl)
	end
end

local contexts, skbcontexts = corpus.packets(), corpus.skbpackets()

-- every read over each packet twice, through ctx:packet() and through skb:data()
local rows = corpus.new()
for _, name in ipairs(order) do
	for i, packet in ipairs(packets.order) do
		rows:stores(name .. i, xdp(reads[name]), action.PASS, contexts[packet])
		rows:stores("skb" .. name .. i, sched(reads[name]), tc.OK, skbcontexts[packet])
	end
end
for i, packet in ipairs(packets.order) do
	rows:stores("inline" .. i, makers.inline, action.PASS, contexts[packet])
	rows:stores("skbinline" .. i, makers.skbinline, tc.OK, skbcontexts[packet])
	rows:stores("joined" .. i, makers.joined, action.PASS, contexts[packet])
end
rows:close()

