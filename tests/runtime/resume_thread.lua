--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the resume/thread chaining test (see resume_thread.sh). Spawned,
-- because thread.run is refused during module load, which is also why echod does this
-- from its daemon thread.

local lunatik = require("lunatik")
local fifo    = require("fifo")
local thread  = require("thread")
local linux   = require("linux")

local SCRIPT  <const> = "tests/runtime/resume_thread_body"
local MESSAGE <const> = "resumed and spawned"

local function driver()
	local runtime = lunatik.runtime(SCRIPT)
	local queue = fifo.new(64)
	local returned = runtime:resume(queue)
	thread.run(runtime, "resume_thread") -- the body pushes and returns, ending the thread

	local got = ""
	for _ = 1, 40 do
		got = queue:pop(#MESSAGE) or ""
		if got ~= "" then break end
		linux.schedule(50)
	end

	if returned ~= nil then
		print("resume_thread: FAIL resume returned a value to its caller")
	elseif got ~= MESSAGE then
		print("resume_thread: FAIL the thread body did not run: '" .. got .. "'")
	else
		print("resume_thread: PASS the thread body ran with what resume left behind")
	end

	while not thread.shouldstop() do
		linux.schedule(100)
	end
end

return driver

