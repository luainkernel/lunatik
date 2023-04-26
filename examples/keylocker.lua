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

