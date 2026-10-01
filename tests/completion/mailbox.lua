--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the mailbox test (see run.sh).

local mailbox = require("mailbox")
local test    = require("tests.lib").test

local pack   = table.pack
local format = string.format

local CAPACITY <const> = 64
local TIMEOUT  <const> = 10 -- ms
local MESSAGE  <const> = "hello"
local QUEUED   <const> = string.packsize("T") + #MESSAGE -- a send queues the length, then the message

local function nothing(inbox, timeout)
	local answer = pack(inbox:receive(timeout))
	assert(answer.n == 1 and answer[1] == nil,
		format("receive(%d) answered %d values, the first %s", timeout, answer.n, tostring(answer[1])))
end

test("mailbox:receive answers nil when the wait elapses", function()
	local inbox = mailbox.inbox(CAPACITY)
	nothing(inbox, TIMEOUT)
	nothing(inbox, 0)
end)

test("mailbox:receive answers a message sent before it", function()
	local inbox = mailbox.inbox(CAPACITY)
	local outbox = mailbox.outbox(inbox.queue, inbox.event)
	outbox:send(MESSAGE)
	local message, length = inbox:receive(TIMEOUT)
	assert(message == MESSAGE and length == #MESSAGE, "receive answered " .. tostring(message))
end)

test("mailbox:send answers false when the queue has no room, and the receiver never sees it", function()
	local inbox = mailbox.inbox(QUEUED)
	local outbox = mailbox.outbox(inbox.queue, inbox.event)
	assert(outbox:send(MESSAGE) == true, "a send into an empty queue was refused")
	assert(outbox:send(MESSAGE) == false, "a send into a full queue was not refused")
	assert(inbox:receive(TIMEOUT) == MESSAGE, "the queued message was lost")
	nothing(inbox, 0)
end)

