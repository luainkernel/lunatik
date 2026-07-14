--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local tc      = require("tc")
local action  = require("linux.tc")
local skbattr = require("skb.attr")
local map     = require("ebpf.map")

local TC_H_MAKE = function(maj, min) return (maj << 16) | min end

local stats = map.open("/sys/fs/bpf/flow_stats")

-- struct flow_stats {
--     u64 packets;
--     u32 avg_pkt_size;
-- };

local KEY_FMT = "<I4"
local VAL_FMT = "<I8I4"

local function qos(ctx)
	local skb = skbattr(ctx:skb())
	local hash = skb.hash
	if hash == 0 then
		ctx:action(action.ACT_OK)
		return
	end
	local key = string.pack(KEY_FMT, hash)
	local value = stats:lookup(key)

	local packets, avg

	if value then
		packets, avg = string.unpack(VAL_FMT, value)
	else
		packets = 0
		avg = 0
	end

	packets = packets + 1
	if packets == 1 then
		avg = #skb
	else
		avg = (avg * 7 + #skb) // 8
	end

	value = string.pack(VAL_FMT, packets, avg)

	stats:update(key, value)

	if avg < 256 then
		skb.priority = TC_H_MAKE(1, 10)
	elseif avg < 800 then
		skb.priority = TC_H_MAKE(1, 20)
	else
		skb.priority = TC_H_MAKE(1, 30)
	end

	ctx:action(action.ACT_OK)
end

tc.attach(qos)

