--
-- SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only 
--

local fifo = require("fifo")

local mailbox = {} 
local MailBox = {}
MailBox.__index = MailBox

local function new(o, allowed, forbidden)
	local mbox = {}
	mbox.queue = type(o) == 'userdata' and o or fifo.new(o)
	mbox[forbidden] = function () error(allowed .. "-only mailbox") end
	return setmetatable(mbox, MailBox)
end

function mailbox.inbox(o)
	return new(o, 'receive', 'send')
end

function mailbox.outbox(o)
	return new(o, 'send', 'receive')
end

local sizeoft = string.packsize("T")
function MailBox:receive()
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
	return self.queue:push(string.pack("s", message))
end

return mailbox

