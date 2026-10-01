--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the tc re-attach test (see test_tc.sh).

local tc     = require("tc")
local action = require("linux.tc")

local function replaced(ctx)
	print("tc reattach test fail: the replaced callback ran")
	return action.ACT_SHOT
end

local function current(ctx)
	print("tc reattach test pass: re-attach installed the last callback")
	return action.ACT_OK
end

tc.attach(replaced)
tc.attach(current)
collectgarbage() -- the replaced context goes, and its skb lets go of its views
collectgarbage() -- the views go

