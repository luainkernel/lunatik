--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink addr_list test (see addr_list.sh).

local netlink = require("netlink")

local LOOPBACK <const> = string.char(127, 0, 0, 1)
local LOCAL4   <const> = string.char(192, 0, 2, 1)
local PEER4    <const> = string.char(192, 0, 2, 2)
local PLAIN4   <const> = string.char(192, 0, 2, 3)
local PREFIX6  <const> = string.char(0x20, 0x01, 0x0d, 0xb8) .. ("\0"):rep(11) -- 2001:db8::/120
local LOCAL6   <const> = PREFIX6 .. "\1"
local PEER6    <const> = PREFIX6 .. "\2"
local PLAIN6   <const> = PREFIX6 .. "\3"

local addr <close> = netlink.rt.addr()
local records = addr:list()

local function find(address)
	for _, record in ipairs(records) do
		if record.address == address then return record end
	end
end

local function say(case)
	print("netlink addr_list: " .. case)
end

local function report(case, address, peer)
	local record = find(address)
	if record and record.peer == peer then say(case) end
end

local loopback = find(LOOPBACK)
if loopback then
	say("127.0.0.1 found")
	if loopback.prefixlen == 8 then say("prefixlen ok") end
	if loopback.peer == nil then say("loopback without peer") end
end

report("ipv4 peer", LOCAL4, PEER4)
report("ipv4 without peer", PLAIN4, nil)
report("ipv6 peer", LOCAL6, PEER6)
report("ipv6 without peer", PLAIN6, nil)

