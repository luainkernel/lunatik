--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local fifo       = require("fifo")
local completion = require("completion")

local lunatik    = require("lunatik")

-- Mailbox using fifo and completion

local mailbox = {}
local MailBox = {}
MailBox.__index = MailBox

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

-- Constructor using rcu
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

function mailbox.inbox(name, q, e)
	if type(name) ~= "string" then
		q, e = name, q
		return new(q, e, 'receive', 'send')
	end
	return new_rcu(name, q, e, 'receive', 'send')
end

function mailbox.outbox(name, q, e)
	if type(name) ~= "string" then
		q, e = name, q
		return new(q, e, 'send', 'receive')
	end
	return new_rcu(name, q, e, 'send', 'receive')
end


local sizeoft = string.packsize("T")
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

function MailBox:send(message)
	self.queue:push(string.pack("s", message))
	if self.event then self.event:complete() end
end


return mailbox
