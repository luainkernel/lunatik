--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only 
--

local fifo       = require("fifo")
local completion = require("completion")

local mailbox = {} 
local MailBox = {}
MailBox.__index = MailBox

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

function mailbox.inbox(q, e)
	return new(q, e, 'receive', 'send')
end

function mailbox.outbox(q, e)
	return new(q, e, 'send', 'receive')
end

local sizeoft = string.packsize("T")
function MailBox:receive()
	local ok, err = self.event:wait()
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

function MailBox:send(message)
	self.queue:push(string.pack("s", message))
	self.event:complete()
end

return mailbox

