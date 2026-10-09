--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the notifier code test (see code.sh).

local notifier = require("notifier")
local netdev   = require("linux.netdev").cmd
local notify   = require("linux.notify")

local WIDE <const> = 5000 -- past MAX_ERRNO once notifier_to_errno reads it

local codes = {
	codewide0 = WIDE,
	codestr0  = tostring(notify.BAD),
	codepast0 = notify.BAD + 1,
	codeneg0  = -1,
	codebad0  = notify.BAD,
}

local function cb(event, name)
	if event == netdev.REGISTER then
		return codes[name]
	end
end

notifier.netdevice(cb)

