--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier namespace test (see netns_scope.sh).

local notifier = require("notifier")
local linux    = require("linux")
local netdev   = require("linux.netdev")
local notify   = require("linux.notify")
local pids     = require("tests.netns_pid")

local INIT <const> = 1 -- pid 1 lives in the initial namespace, so its netns is linux.netns()

local events = {[netdev.REGISTER] = "register", [netdev.UNREGISTER] = "unregister"}

local function cb(event, name, netns)
	local kind = events[event]
	if kind then
		print(("netns scope: %s %s %d"):format(kind, name, netns))
	end
	return notify.OK
end

print(("netns scope: home %d task %d holder %d"):format(linux.netns(), linux.netns(INIT), linux.netns(pids.holder)))
local ok, err = pcall(linux.netns, pids.reaped)
assert(not ok and err == "ESRCH", "a reaped pid should raise ESRCH, got " .. tostring(err))
ok, err = pcall(linux.netns, 0)
assert(not ok and err:match("out of bounds"), "pid 0 should be out of bounds, got " .. tostring(err))
print("netns scope: reaped pid raises ESRCH, pid 0 is out of bounds")
notifier.netdevice(cb)

