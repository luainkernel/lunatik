--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Child script for the self_stop test (see self_stop.sh): stops, resumes and threads itself from its body.

local lunatik = require("lunatik")
local thread  = require("thread")

local PREFIX <const> = "self_stop test: "
local NAME   <const> = "self_stop"

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""))
end

local function report(label, ...)
	print(PREFIX .. label .. verdict(...))
end

local function body(self)
	local label = lunatik.cpu() and "percpu self " or "self "
	report(label .. "stop ", pcall(self.stop, self))
	report(label .. "resume ", pcall(self.resume, self))
	if not lunatik.cpu() then -- a thread runs on a runtime, not on a set
		report(label .. "thread ", pcall(thread.run, self, NAME))
	end
end

return body

