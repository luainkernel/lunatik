--
-- SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local notifier = require("notifier")

-- <UP> <UP> <DOWN> <DOWN> <LEFT> <RIGHT> <LEFT> <RIGHT> <LCTRL> <LALT>
local konami = {code = {103, 103, 108, 108, 105, 106, 105, 106, 29, 56}, ix = 1}
function konami:completion(key)
	self.ix = key == self.code[self.ix] and (self.ix + 1) or 1
	return self.ix == (#self.code + 1)
end

local notify = notifier.notify
local kbd    = notifier.kbd
local enable = true
local function locker(event, down, shift, key)
	if not down and event == kbd.KEYCODE and konami:completion(key) then
		enable = not enable
	end
	return enable and notify.OK or notify.STOP
end

notifier.keyboard(locker)

