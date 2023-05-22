--
-- Copyright (c) 2023 ring-0 Ltda.
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--

local device = require("device")
local socket = require("socket")
local linux  = require("linux")

local PACKET    = socket.af.PACKET
local RAW       = socket.sock.RAW
local ETH_P_ALL = 0x0003
local MTU       = 1500

local function nop() end

local s = linux.stat
local tap = {name = "tap", open = nop, release = nop, mode = s.IRUGO}

local socket = socket.new(PACKET, RAW, ETH_P_ALL)
socket:bind(string.pack(">I2", ETH_P_ALL))

function tap:read()
	local frame = socket:receive(MTU)
	local dst, src, ethtype = string.unpack(">I6I6I2", frame)
	return string.format("%X\t%X\t%X\t%d\n", dst, src, ethtype, #frame)
end

device.new(tap)

