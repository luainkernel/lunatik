--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the scx runqueue test (see run.sh).

local lunatik    = require("lunatik")
local scx        = require("scx")
local rcu        = require("rcu")
local completion = require("completion")
local mailbox    = require("mailbox")

local REFUSAL <const> = "not allowed under the runqueue lock"
local MESSAGE <const> = "scx runqueue"
local QUEUED  <const> = string.pack("s", MESSAGE)
local PRINTED <const> = "scx runqueue printed"
local WARNED  <const> = "scx runqueue warned"
local GCERROR <const> = "scx runqueue collected"

local record = rcu.table()
lunatik._ENV["scx runqueue"] = record

local event  = completion.new()
local outbox = mailbox.outbox(64)

local function refused(method, object, ...)
	local ok, err = pcall(method, object, ...)
	return not ok and tostring(err):find(REFUSAL, 1, true) ~= nil
end

local function write()
	print(PRINTED)
	warn(WARNED)
	setmetatable({}, {__gc = function() error(GCERROR, 0) end})
	collectgarbage()
	record.written = true
end

-- each step records that the one before it returned to the dispatch

local function wake()
	record.complete = refused(event.complete, event)
	record.send = refused(outbox.send, outbox, MESSAGE)
	record.queued = outbox.queue:pop(#QUEUED) == QUEUED
	event:complete()
end

local function decide()
	record.raised = true
	return "global"
end

local function detach()
	record.decided = true
	scx.detach()
	record.detached = true
end

local steps = {write, wake, decide, detach}
local step = 0

local function enqueue()
	step = step + 1
	return steps[step]()
end

scx.attach(enqueue)

