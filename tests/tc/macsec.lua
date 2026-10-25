--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc macsec case (see test_tc.sh).

local tc      = require("tc")
local action  = require("linux.tc").action
local packet  = require("tests.tc.packet")
local forward = require("tests.tc.forward")

local REFUSAL <const> = "copy would leave unencrypted"

-- the third byte of the IPv4 destination names the subnet each ping goes to: 10.199.9.0/24 through
-- the MACsec device, 10.199.10.0/24 out of its port
local DSTNET <const> = 32
local cells = {[9] = "secured", [10] = "plain"}

local function report(cell, failure)
	print("tc macsec: " .. cell .. (failure and " FAIL " .. failure or " ok"))
end

local function refused(skb)
	return forward.refuses(skb:copy(), REFUSAL)
end

local function sent(skb)
	local ok, err = pcall(skb.forward, skb:copy())
	return not ok and err or nil
end

local checks = {secured = refused, plain = sent}

local function test_macsec(ctx)
	local skb = ctx:skb()
	local data = skb:data()
	local cell = packet.isecho(data) and cells[data:getuint8(DSTNET)]
	if cell then
		report(cell, checks[cell](skb))
	end
	return action.OK
end

tc.attach(test_macsec)

