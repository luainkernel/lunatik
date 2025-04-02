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

local lunatik    = require("lunatik")

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
	-- Setting e to false makes this Mailbox non-blocking,
	-- hence suitable for non-sleepable runtimes.
	local mbox = {}
	if type(q) == 'userdata' then
		mbox.queue, mbox.event = q, e
	else
		mbox.queue = fifo.new(q)
		if e ~= false then
			mbox.event = completion.new()
		end
	end
	mbox[forbidden] = function () error(allowed .. "-only mailbox") end
	return setmetatable(mbox, MailBox)
end

---
-- Internal constructor for mailbox objects using RCU (Read-Copy-Update) mechanism.
-- This function is used to create mailboxes that are shared across runtimes
-- using the `lunatik._ENV` table for synchronization.
-- @tparam string name The name of the mailbox in the `lunatik._ENV` table.
-- @tparam (fifo|number|boolean) q Either an existing FIFO object, a capacity for a new FIFO, or `false` for a non-blocking mailbox.
-- @tparam[opt] completion e An existing completion object. If `nil` and `q` is a number, a new completion is created. If `false`, the mailbox is non-blocking.
-- @tparam string allowed The allowed operation ("send" or "receive").
-- @tparam string forbidden The forbidden operation ("send" or "receive").
-- @treturn MailBox The new mailbox object.
-- @local
-- @usage
-- local my_inbox = mailbox.inbox("my_shared_mailbox")
-- local my_outbox = mailbox.outbox("my_shared_mailbox")
-- my_outbox:send("hello from outbox")
-- local msg = my_inbox:receive() -- msg will be "hello from outbox"
local env = lunatik._ENV
local function new_rcu(name, q, e, allowed, forbidden)
	if q == false then  -- Makes it possible to create a non-blocking mailbox as follows: mailbox.rcu "my_mbox", false
		e = q
	end
	q = q or 10240
	local mbox
	local queue = env[name]
	if queue then
		mbox = new(queue, e, allowed, forbidden)
		-- The following functions are a guard against race conditions
		function mbox:receive(message)
			self.queue, self.receive, self.send = env[name], nil, nil
			MailBox.receive(self, message)
		end
		function mbox:send(message)
			self.queue, self.receive, self.send = env[name], nil, nil
			MailBox.send(self, message)
		end
	else
		mbox = new(q, e, allowed, forbidden)
		env[name] = mbox.queue
	end
	return mbox
end

---
-- Creates a new inbox (receive-only) mailbox.
-- An inbox allows messages to be received. Sending messages to an inbox will result in an error.
-- @function mailbox.inbox
-- @tparam[opt] string name The name of the mailbox for RCU sharing across runtimes. If omitted, a local mailbox is created.
-- @tparam[opt] (fifo|number|boolean) q Either an existing FIFO object, a capacity for a new FIFO, or `false` for a non-blocking mailbox. Defaults to 10240 if `name` is provided.
-- @tparam[opt] completion e An existing completion object. If `nil` and `q` is a number, a new completion is created. If `false`, the mailbox is non-blocking.
-- @treturn MailBox The new inbox mailbox object.
-- @usage
-- -- Create a local inbox with a capacity of 1024 bytes
-- local my_inbox = mailbox.inbox(1024)
--
-- -- Non-blocking receive (returns immediately if no message)
-- local msg = my_inbox:receive(0)
-- if not msg then
--   print("No message available")
-- end
--
-- -- Create an inbox from an existing outbox's queue and event
-- local existing_outbox = mailbox.outbox(2048)
-- local paired_inbox = mailbox.inbox(existing_outbox.queue, existing_outbox.event)
--
-- -- Shared inbox example:
-- local shared_inbox = mailbox.inbox("global_messages")
-- local msg = shared_inbox:receive()
-- @within mailbox
function mailbox.inbox(name, q, e)
	if type(name) ~= "string" then
		q, e = name, q
		return new(q, e, 'receive', 'send')
	end
	return new_rcu(name, q, e, 'receive', 'send')
end

---
-- Creates a new outbox (send-only) mailbox.
-- An outbox allows messages to be sent. Receiving messages from an outbox will result in an error.
-- @function mailbox.outbox
-- @tparam[opt] string name The name of the mailbox for RCU sharing across runtimes. If omitted, a local mailbox is created.
-- @tparam[opt] (fifo|number|boolean) q Either an existing FIFO object, a capacity for a new FIFO, or `false` for a non-blocking mailbox. Defaults to 10240 if `name` is provided.
-- @tparam[opt] completion e An existing completion object. If `nil` and `q` is a number, a new completion is created. If `false`, the mailbox is non-blocking.
-- @treturn MailBox The new outbox mailbox object.
-- @usage
-- -- Create a local outbox with a capacity of 2048 bytes
-- local my_outbox = mailbox.outbox(2048)
-- my_outbox:send("hello")
--
-- -- Create an outbox from an existing inbox's queue and event
-- local existing_inbox = mailbox.inbox(1024)
-- local paired_outbox = mailbox.outbox(existing_inbox.queue, existing_inbox.event)
--
-- -- Shared outbox example:
-- local shared_outbox = mailbox.outbox("global_messages")
-- shared_outbox:send("another message")
-- @within mailbox
function mailbox.outbox(name, q, e)
	if type(name) ~= "string" then
		q, e = name, q
		return new(q, e, 'send', 'receive')
	end
	return new_rcu(name, q, e, 'send', 'receive')
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
-- @usage
-- -- Blocking receive (waits indefinitely)
-- local msg = my_inbox:receive()
--
-- -- Non-blocking receive (returns immediately if no message)
-- local msg = my_inbox:receive(0)
-- if not msg then
--   print("No message available")
-- end
--
-- -- Blocking receive with timeout (waits for 100 jiffies)
-- local msg = my_inbox:receive(100)
-- if not msg then
--   print("Timeout: No message received within 100 jiffies")
-- end
function MailBox:receive(timeout)
	-- Setting timeout = 0 makes this function non-blocking.
	if self.event and timeout ~= 0 then
		local ok, err = self.event:wait(timeout)
		if not ok then error(err) end
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
-- @tparam string message The message to send.
-- @raise Error if called on an inbox.
-- @usage
-- local my_outbox = mailbox.outbox(1)
-- my_outbox:send("important message") -- This will complete the event, potentially waking up a receiver.
function MailBox:send(message)
	self.queue:push(string.pack("s", message))
	if self.event then self.event:complete() end
end


return mailbox

