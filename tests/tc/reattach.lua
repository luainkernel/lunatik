--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc re-attach test (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc").action

local function replaced()
	print("tc reattach test fail: the replaced callback ran")
	return action.SHOT
end

local function current()
	print("tc reattach test pass: re-attach installed the last callback")
	return action.OK
end

tc.attach(replaced)
tc.attach(current)
collectgarbage() -- the replaced context goes, and its skb lets go of its views
collectgarbage() -- the views go

