--- Inter-runtime communication via FIFOs and completions.
-- @module mailbox
-- @see fifo
-- @see completion

local fifo       = require("fifo")
local completion = require("completion")

--- @table mailbox
local mailbox = {} 

--- @type MailBox
-- @field queue (fifo) Underlying FIFO queue.
-- @field event (completion) Synchronization object.
local MailBox = {}
MailBox.__index = MailBox

--- Internal constructor.
-- @param q (fifo|number) Existing FIFO or new FIFO capacity.
-- @param e (completion) [opt] Existing completion.
-- @param allowed (string) Allowed operation ("send" or "receive").
-- @param forbidden (string) Forbidden operation ("send" or "receive").
-- @return (MailBox) New mailbox.
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

--- Creates a new inbox (receive-only).
-- @param q (fifo|number) Existing FIFO or new FIFO capacity.
-- @param e (completion) [opt] Existing completion.
-- @return (MailBox) New inbox.
-- @usage local inbox = mailbox.inbox(10)
function mailbox.inbox(q, e)
	return new(q, e, 'receive', 'send')
end

--- Creates a new outbox (send-only).
-- @param q (fifo|number) Existing FIFO or new FIFO capacity.
-- @param e (completion) [opt] Existing completion.
-- @return (MailBox) New outbox.
-- @usage local outbox = mailbox.outbox(10)
function mailbox.outbox(q, e)
	return new(q, e, 'send', 'receive')
end

local sizeoft = string.packsize("T")

--- Receives a message. Blocks until available or timeout.
-- Not available on outboxes.
-- @function MailBox:receive
-- @tparam[opt] number timeout Timeout in jiffies.
-- @treturn[1] string Received message.
-- @treturn[1] nil If no message (e.g. empty after event or timeout).
-- @treturn[2] string Error message on timeout or failure.
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

--- Sends a message.
-- Not available on inboxes.
-- @function MailBox:send
-- @tparam string message Message to send.
function MailBox:send(message)
	self.queue:push(string.pack("s", message))
	self.event:complete()
end

return mailbox

