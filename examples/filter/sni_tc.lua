--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local tc = require("tc")

local action = tc.action

local function filter_sni(packet, argument)
	print("luatc hit")
	return action.OK
end

tc.attach(filter_sni)
