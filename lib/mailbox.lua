--
-- SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only 
--

---
-- Inter-runtime communication mechanism using FIFOs and completions.
-- This module provides a way for different Lunatik runtimes (Lua states)
-- to send and receive messages to/from each other. It uses a FIFO queue
-- for message storage and a completion object for synchronization.
--
-- Mailboxes are unidirectional (`inbox` for receiving only, `outbox` for sending only).
-- Messages are serialized as strings.
--
-- The receiver creates the inbox and hands its `queue` and `event` to the other runtime, as
-- through `runtime:resume`, where the sender builds `mailbox.outbox(queue, event)`: a mailbox
-- built on an existing fifo needs its completion too. `send` works in any context; `receive`
-- sleeps, and a softirq or hardirq runtime refuses it.
--
-- @module mailbox
-- @see fifo
-- @see completion
-- @usage
-- -- receiver.lua, run with `lunatik run receiver`
-- local lunatik = require("lunatik")
-- local mailbox = require("mailbox")
--
-- local inbox = mailbox.inbox(4096)
-- local sender <close> = lunatik.runtime("sender")
-- sender:resume(inbox.queue, inbox.event)
-- print(inbox:receive(1000)) -- hello 5
--
-- -- sender.lua
-- local mailbox = require("mailbox")
--
-- local function send(queue, event)
-- 	mailbox.outbox(queue, event):send("hello")
-- end
-- return send
--

local fifo       = require("fifo")
local completion = require("completion")

local mailbox = {} 

---
-- Metatable for MailBox objects.
-- This table defines the methods available on mailbox instances.
-- @type MailBox
-- @field queue (fifo) The underlying FIFO queue used for message storage.
-- @field event (completion) The completion object used for synchronization.
local MailBox = {}
MailBox.__index = MailBox

---
-- Internal constructor for mailbox objects.
-- @param q (fifo|number) Either an existing FIFO object or a capacity for a new FIFO.
-- @param e (completion) [optional] An existing completion object. If nil and `q` is a number, a new completion is created.
-- @param allowed (string) The allowed operation ("send" or "receive").
-- @param forbidden (string) The forbidden operation ("send" or "receive").
-- @return (MailBox) The new mailbox object.
-- @local
local function new(q, e, allowed, forbidden)
	local mbox = {}
	if type(q) == 'userdata' then
		mbox.queue, mbox.event = q, e
	else
		mbox.queue, mbox.event = fifo.new(q), completion.new()
	end
	mbox[forbidden] = function () error(allowed .. "-only mailbox") end
	return setmetatable(mbox, MailBox)
end

---
-- Creates a new inbox (receive-only mailbox).
-- @param q (fifo|number) Either an existing FIFO object or a capacity for a new FIFO, at least
--   `string.packsize("T")` bytes: `receive()` pops a header of that size.
-- @param e (completion) [optional] An existing completion object. If nil and `q` is a number,
--   a new completion object will be created.
-- @return (MailBox) A new inbox object.
-- @usage
--   local my_inbox = mailbox.inbox(4096) -- 4096 bytes; a message takes its length plus a size_t
--   local msg = my_inbox:receive()
-- @within mailbox
function mailbox.inbox(q, e)
	return new(q, e, 'receive', 'send')
end

---
-- Creates a new outbox (send-only mailbox).
-- @param q (fifo|number) Either an existing FIFO object or a capacity for a new FIFO, at least
--   `string.packsize("T")` bytes: `receive()` pops a header of that size.
-- @param e (completion) [optional] An existing completion object. If nil and `q` is a number,
--   a new completion object will be created.
-- @return (MailBox) A new outbox object.
-- @usage
--   local my_outbox = mailbox.outbox(4096) -- 4096 bytes; a message takes its length plus a size_t
--   my_outbox:send("hello")
-- @within mailbox
function mailbox.outbox(q, e)
	return new(q, e, 'send', 'receive')
end

local sizeoft = string.packsize("T")

---
-- Receives a message from the mailbox.
-- This function will block until a message is available or the timeout expires.
-- Not available on outboxes.
-- @function MailBox:receive
-- @tparam[opt] number timeout maximum time to wait in milliseconds, from 0 to `2^31 - 1`.
--   If omitted or nil, waits indefinitely. If 0, returns immediately.
-- @treturn string|nil the message, or `nil` if the wait elapsed, timeout 0 on an empty mailbox
--   included, or the event fired with the queue empty.
-- @treturn integer the message's length, beside a message.
-- @raise "send-only mailbox" on an outbox; "out of bounds" for a timeout outside its range;
--   `ERESTARTSYS` when a signal or `thread:stop()`
--   interrupts the wait; "malformed message" on a truncated header; "runtime context mismatch"
--   from a softirq or hardirq runtime.
function MailBox:receive(timeout)
	if not self.event:wait(timeout) then
		return nil
	end

	local queue = self.queue
	local header, header_size = queue:pop(sizeoft)

	if header_size == 0 then
		return nil
	elseif header_size < sizeoft then
		error("malformed message")
	end

	return queue:pop(string.unpack("T", header))
end

---
-- Sends a message to the mailbox.
-- Not available on inboxes.
-- @function MailBox:send
-- @tparam string message message to send.
-- @treturn boolean `true` if the message was queued, `false` if the queue has no room for it.
-- @raise "receive-only mailbox" on an inbox; "out of bounds" for a message whose length plus a
--   `size_t` exceeds the queue's capacity.
function MailBox:send(message)
	local queued = self.queue:push(string.pack("s", message))
	if queued then
		self.event:complete()
	end
	return queued
end

return mailbox

