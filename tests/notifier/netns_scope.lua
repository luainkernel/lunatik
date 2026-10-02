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
local PAST_LIMIT <const> = (4 << 20) + 1 -- one past PID_MAX_LIMIT where it is largest, 64-bit
local WRAP <const> = 1 << 32

local events = {[netdev.REGISTER] = "register", [netdev.UNREGISTER] = "unregister"}

local function cb(event, name, netns)
	local kind = events[event]
	if kind then
		print(("netns scope: %s %s %d"):format(kind, name, netns))
	end
	return notify.OK
end

print(("netns scope: home %d task %d holder %d"):format(linux.netns(), linux.netns(INIT), linux.netns(pids.holder)))
for _, pid in ipairs({pids.reaped, pids.zombie}) do
	local inum, err = linux.netns(pid)
	assert(inum == nil and err == "ESRCH",
		("pid %d should answer nil and ESRCH, got %s, %s"):format(pid, tostring(inum), tostring(err)))
end
for _, pid in ipairs({0, PAST_LIMIT, WRAP + pids.holder}) do
	local ok, err = pcall(linux.netns, pid)
	assert(not ok and err:match("out of bounds"), "pid " .. pid .. " should be out of bounds, got " .. tostring(err))
end
print("netns scope: reaped pid and zombie answer nil and ESRCH, pids out of bounds raise")
notifier.netdevice(cb)

