--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the forward test (see forward.sh).

local filter    = require("tests.skb.filter")
local nf        = require("linux.nf")
local ipproto   = require("linux.socket").ipproto
local linux     = require("linux")

local IP_PROTO    <const> = 9
local ICMP_TYPE   <const> = 20 -- past an IPv4 header without options, as ping sends it
local ECHO        <const> = 8
local PAST_MARK   <const> = 1291 -- PAST_MARK in forward.sh
local BEFORE_MARK <const> = 1292 -- BEFORE_MARK in forward.sh
local AT_MARK     <const> = 1293 -- AT_MARK in forward.sh
local COPY_MARK   <const> = 1294 -- COPY_MARK in forward.sh
local REFUSAL     <const> = "MAC header past the data"
local SOURCE      <const> = 11 -- the last byte of the Ethernet source address
local FLIP        <const> = 0xff -- the bits a write after forward() changes

local format = string.format

local cells = {[BEFORE_MARK] = "before", [AT_MARK] = "at", [COPY_MARK] = "copy"}
local forwarded = {}
local stamp = linux.random(1, FLIP) -- drawn per run, so a copy whose MAC bytes were never written reads another

local function past(skb)
	if skb:data():getuint8(IP_PROTO) ~= ipproto.IPIP then
		return nf.action.ACCEPT
	end
	local ok, err = pcall(skb.forward, skb)
	if ok then
		print("skb forward: past FAIL a copy was sent")
	elseif err:find(REFUSAL, 1, true) then
		print("skb forward: past ok")
	else
		print("skb forward: past FAIL " .. err)
	end
	return nf.action.DROP
end

-- the frame forward() sent reads what the view held before it, not what was written after
local function written(view, offset, want)
	local got = view:getuint8(offset)
	return got ~= want and format("byte %d reads %d, not %d", offset, got, want)
end

-- a copy's views, taken before forward(), still read its own head after the resize that follows
local function resendcopy(skb)
	local copy = skb:copy()
	local packet, mac = copy:data(), copy:data("mac")
	local last = #packet - 1
	mac:setuint8(SOURCE, stamp)
	forwarded.copy = packet:getuint8(last)
	copy:forward()
	copy:resize(#copy + 1)
	packet:setuint8(last, forwarded.copy ~ FLIP)
	mac:setuint8(SOURCE, stamp ~ FLIP)
	return nf.action.ACCEPT
end

local function resend(skb)
	local packet = skb:data()
	if packet:getuint8(IP_PROTO) ~= ipproto.ICMP or packet:getuint8(ICMP_TYPE) ~= ECHO then
		return nf.action.ACCEPT
	end
	local cell = cells[skb:mark()]
	local mac, last = skb:data("mac"), #packet - 1
	local header = #mac > #packet -- the MAC header lies before skb->data
	local byte = forwarded[cell]
	if byte then
		local failure = written(packet, last, byte) or header and written(mac, SOURCE, stamp)
		print("skb forward: " .. cell .. (failure and " FAIL " .. failure or " ok"))
		return nf.action.ACCEPT
	end
	if cell == "copy" then
		return resendcopy(skb)
	end
	if header then
		mac:setuint8(SOURCE, stamp)
	end
	forwarded[cell] = packet:getuint8(last)
	skb:forward()
	packet:setuint8(last, forwarded[cell] ~ FLIP)
	if header then
		mac:setuint8(SOURCE, stamp ~ FLIP)
	end
	return nf.action.ACCEPT
end

filter.register(past, nf.proto.INET, nf.inet.LOCAL_OUT, PAST_MARK)

for mark in pairs(cells) do
	filter.register(resend, nf.proto.INET, nf.inet.PRE_ROUTING, mark)
end

