--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Devices for the killable test (see killable.sh).

local lunatik = require("lunatik")
local device  = require("device")
local linux   = require("linux")
local verdict = require("tests.runtime.verdict")

local HOLDER  <const> = "tests/runtime/killable_holder"
local BLOCKED <const> = "tests/runtime/killable_blocked"
local SETTLE  <const> = 200
local PREFIX  <const> = "killable test: fop "

local env = lunatik._ENV

local waiter = {name = "lunatik_killable"}

function waiter:read()
	local runtime = env.runtimes[HOLDER]
	verdict.report(PREFIX, "resume", pcall(runtime.resume, runtime))
	return ""
end

local stopper = {name = "lunatik_killable_stop"}

function stopper:read()
	linux.schedule(SETTLE) -- under this runtime's lock, for the blocked thread to wait on it
	local t = env.threads[BLOCKED]
	verdict.report(PREFIX, "stop", pcall(t.stop, t))
	return ""
end

device.new(waiter)
device.new(stopper)

