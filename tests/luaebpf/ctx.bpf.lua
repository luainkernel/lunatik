--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the ctx case (see ctx.sh).

local corpus  = require("tests.luaebpf.corpus")
local vmlinux = require("luaebpf.vmlinux")
local tc      = require("bpf.tc")

-- loopback, whose generic rx queue 0 has its xdp_rxq registered on every device, which is what
-- xdp_convert_md_to_buff requires of a non-zero ingress_ifindex, and the device prog run builds
-- an skb on unless ctx_in names one above it, which skb:ifindex() reads (net/bpf/test_run.c)
local IFINDEX <const> = 1
local QUEUE   <const> = 0
local PRIO    <const> = 5
local WRITTEN <const> = 77
local U32MAX  <const> = 0xffffffff
-- an ethertype no IP header follows: an skb test run refuses an IPv4 one whose header is missing
local FRAME   <const> = "\xff\xff\xff\xff\xff\xff\x00\x11\x22\x33\x44\x55\x88\xb5"

local function ingress(keep)
	return function(ctx)
		local ifindex = ctx:ingress()
		keep(ifindex)
	end
end

local function queue(keep)
	return function(ctx)
		local index = ctx:queue()
		keep(index)
	end
end

local function both(keep)
	return function(ctx)
		local v = ctx:ingress() * 100 + ctx:queue()
		keep(v)
	end
end

local function skblen(keep)
	return function(skb)
		keep(#skb)
	end
end

local function skbifindex(keep)
	return function(skb)
		local ifindex = skb:ifindex()
		keep(ifindex)
	end
end

local function skbhash(keep)
	return function(skb)
		local hash = skb:hash()
		keep(hash)
	end
end

local function skbpriority(keep)
	return function(skb)
		local priority = skb:priority()
		keep(priority)
	end
end

-- the setter answers the field it stored, read back through the kernel's own context
local function skbsetpriority(keep)
	return function(skb)
		local priority = skb:priority(WRITTEN)
		keep(priority)
	end
end

-- a value the program computes, which the store takes from a register rather than a constant, with
-- the field's top bit set, so the test before the store is held to the field's whole width
local function skbsetlength(keep)
	return function(skb)
		local priority = skb:priority(U32MAX - #skb)
		keep(priority)
	end
end

-- the largest value the field holds, which a store of the low 32 bits keeps as it is
local function skbsetmax(keep)
	return function(skb)
		local priority = skb:priority(U32MAX)
		keep(priority)
	end
end

-- a computed value past the field's 32 bits, and one below zero, which the kernel's setter raises
-- on: the compiled one owes the default verdict, where a store of the low bits would answer them
local function skbsetwide(keep)
	return function(skb)
		local priority = skb:priority(#skb + U32MAX)
		keep(priority)
	end
end

local function skbsetnegative(keep)
	return function(skb)
		local priority = skb:priority(-#skb)
		keep(priority)
	end
end

local xdpctx = corpus.context("xdpctx", "xdp_md",
	{ingress_ifindex = IFINDEX, rx_queue_index = QUEUE}, FRAME)
local skbctx = corpus.context("skbctx", "__sk_buff", {ifindex = IFINDEX, priority = PRIO}, FRAME)
-- each write row gets a context of its own, since it leaves its twin's priority changed
local skbwrite = corpus.context("skbwrite", "__sk_buff", {ifindex = IFINDEX, priority = PRIO}, FRAME)
local skbcomputed = corpus.context("skbcomputed", "__sk_buff", {ifindex = IFINDEX, priority = PRIO}, FRAME)
local skbmax = corpus.context("skbmax", "__sk_buff", {ifindex = IFINDEX, priority = PRIO}, FRAME)

local rows = corpus.new()
rows:stores("ingress", ingress, nil, xdpctx)
rows:stores("queue", queue, nil, xdpctx)
rows:stores("both", both, nil, xdpctx)
rows:stores("skblen", skblen, nil, skbctx)
rows:stores("skbifindex", skbifindex, nil, skbctx)
rows:stores("skbhash", skbhash, nil, skbctx)
rows:stores("skbpriority", skbpriority, nil, skbctx)
rows:stores("skbsetprio", skbsetpriority, nil, skbwrite)
rows:stores("skbsetlen", skbsetlength, nil, skbcomputed)
rows:stores("skbsetmax", skbsetmax, nil, skbmax)
rows:stores("skbsetwide", skbsetwide, nil, skbctx)
rows:stores("skbsetneg", skbsetnegative, nil, skbctx)
-- the length read again on the way out, from the section libbpf reads the egress attach point off
corpus.program(tc.program, {name = "skbegress", egress = true}, skblen)
rows:close()

-- what the case reads ctx_out back at, from the same BTF the emitter lowered the store against
local out = assert(io.open("offsets.txt", "w"))
for _, field in ipairs(vmlinux.layout("__sk_buff").fields) do
	out:write(field.name, "\t", field.offset, "\t", field.size, "\n")
end
out:write("written\t", WRITTEN, "\t0\n")
out:write("held\t", PRIO, "\t0\n")
out:close()

