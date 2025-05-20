--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
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
-- @module mailbox
-- @see fifo
-- @see completion
--

local fifo       = require("fifo")
local completion = require("completion")

---
-- The main mailbox table.
-- @table mailbox
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
-- @param q (fifo|number) Either an existing FIFO object or a capacity for a new FIFO.
--   If a number, a new FIFO with this capacity will be created.
-- @param e (completion) [optional] An existing completion object. If nil and `q` is a number,
--   a new completion object will be created.
-- @return (MailBox) A new inbox object.
-- @usage
--   local my_inbox = mailbox.inbox(10) -- Inbox with capacity for 10 messages
--   local msg = my_inbox:receive()
function mailbox.inbox(q, e)
	return new(q, e, 'receive', 'send')
end

---
-- Creates a new outbox (send-only mailbox).
-- @param q (fifo|number) Either an existing FIFO object or a capacity for a new FIFO.
--   If a number, a new FIFO with this capacity will be created.
-- @param e (completion) [optional] An existing completion object. If nil and `q` is a number,
--   a new completion object will be created.
-- @return (MailBox) A new outbox object.
-- @usage
--   local my_outbox = mailbox.outbox(10) -- Outbox with capacity for 10 messages
--   my_outbox:send("hello")
function mailbox.outbox(q, e)
	return new(q, e, 'send', 'receive')
end

local sizeoft = string.packsize("T")

---
-- Receives a message from the mailbox.
-- This function will block until a message is available or the timeout expires.
-- Not available on outboxes.
-- @function MailBox:receive
-- @tparam[opt] number timeout The maximum time to wait in jiffies.
--   If omitted or negative, waits indefinitely. If 0, returns immediately.
-- @treturn[1] string The received message.
-- @treturn[1] nil If no message is received (e.g., FIFO is empty after event or on timeout).
-- @treturn[2] string Error message if the wait times out or another error occurs.
-- @raise Error if called on an outbox, or if the underlying event wait fails,
--   or if a malformed message is encountered.
function MailBox:receive(timeout)
	local ok, err = self.event:wait(timeout)
	if not ok then error(err) end

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
-- @tparam string message The message to send.
-- @raise Error if called on an inbox.
function MailBox:send(message)
	self.queue:push(string.pack("s", message))
	self.event:complete()
end

return mailbox

