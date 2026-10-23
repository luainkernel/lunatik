--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the copy_device test (see copy_device.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local linux     = require("linux")

local insert = table.insert
local format = string.format

local IFACE      <const> = "lunatikcdev0" -- IFACE in copy_device.sh
local STEP_MARK  <const> = 1310 -- STEP_MARK in copy_device.sh
local COPY_MARK  <const> = 1311
local INNER_MARK <const> = 1312
local IP_PROTO   <const> = 9
local ICMP       <const> = 1
local ICMP_TYPE  <const> = 20 -- past an IPv4 header without options, as ping sends it
local ECHO       <const> = 8
local REFUSAL    <const> = "skb has no device"

local ifindex = linux.ifindex(IFACE)
local marks = {copy = COPY_MARK, inner = INNER_MARK}
local senders = {}
local order = {"inside", "held", "past", "deleted"}
local steps = {}
local kept = {}
local step = 0

local function report(cell, failure)
	print("skb copy device: " .. cell .. (failure and " FAIL " .. failure or " ok"))
end

local function isecho(skb)
	local packet = skb:data()
	return packet:getuint8(IP_PROTO) == ICMP and packet:getuint8(ICMP_TYPE) == ECHO
end

local function keep(skb, name, copy)
	local index, want = copy:ifindex(), skb:ifindex()
	local ifname, wanted = copy:ifname(), skb:ifname()
	insert(kept, {name = name, copy = copy, length = #skb})
	if index ~= want or ifname ~= wanted then
		return format("%s: ifindex %s and ifname %s, not %d and %s", name, index, ifname, want, wanted)
	end
end

local function send(skb, name, copy)
	local failure = keep(skb, name, copy)
	if failure then
		return failure
	end
	copy:mark(marks[name])
	local ok, err = pcall(copy.forward, copy)
	if not ok then
		return name .. ": " .. err
	end
end

-- a copy past its callback: no device, forward() refused, its bytes read
local function answers(copy, length)
	local index, ifname = copy:ifindex(), copy:ifname()
	if index ~= nil or ifname ~= nil then
		return format("ifindex %s and ifname %s", index, ifname)
	end
	local ok, err = pcall(copy.forward, copy)
	if ok then
		return "forward() sent it"
	elseif not err:find(REFUSAL, 1, true) then
		return err
	end
	local data = copy:data()
	local size = #data
	if size ~= length or data:getuint8(ICMP_TYPE) ~= ECHO then
		return format("a view of %d bytes, not the echo request of %d", size, length)
	end
end

function steps.inside(skb)
	local copy = skb:copy()
	skb:copy()
	local inner = copy:copy()
	collectgarbage() -- the copy dropped above goes inside the callback, beside the two it keeps
	return send(skb, "copy", copy) or send(skb, "inner", inner)
end

function steps.held(skb)
	return keep(skb, "veth", skb:copy())
end

function steps.past()
	for _, held in ipairs(kept) do
		local failure = answers(held.copy, held.length)
		if failure then
			return held.name .. ": " .. failure
		end
		failure = answers(held.copy:copy(), held.length)
		if failure then
			return "a copy of " .. held.name .. ": " .. failure
		end
	end
end

steps.deleted = steps.past

local function take(skb)
	step = step + 1
	local cell = order[step]
	report(cell, steps[cell](skb))
	return nf.action.DROP
end

local function lo(skb)
	return isecho(skb) and take(skb) or nf.action.ACCEPT
end

local function veth(skb)
	return skb:ifindex() == ifindex and isecho(skb) and take(skb) or nf.action.ACCEPT
end

local function sent(skb)
	report("sent " .. senders[skb:mark()])
	return nf.action.DROP
end

local function register(hook, mark)
	netfilter.register{
		hook     = hook,
		pf       = nf.proto.IPV4,
		hooknum  = nf.inet.PRE_ROUTING,
		priority = nf.ip.pri.FILTER,
		mark     = mark,
	}
end

register(lo, STEP_MARK)
register(veth)
for name, mark in pairs(marks) do
	senders[mark] = name
	register(sent, mark)
end

