--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local device = require("device")
local socket = require("socket")
local linux  = require("linux")

local PACKET    = socket.af.PACKET
local RAW       = socket.sock.RAW
local ETH_P_ALL = 0x0003
local MTU       = 1500

local s = linux.stat
local tap = {name = "tap", mode = s.IRUGO}

local socket = socket.new(PACKET, RAW, ETH_P_ALL)
socket:bind(string.pack(">I2", ETH_P_ALL))

function tap:read()
	local frame = socket:receive(MTU)
	local dst, src, ethtype = string.unpack(">I6I6I2", frame)
	return string.format("%X\t%X\t%X\t%d\n", dst, src, ethtype, #frame)
end

device.new(tap)

