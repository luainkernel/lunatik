--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Thread body for the thread tests (see run.sh): tells the driver it runs, then waits for a stop.

local wait = require("tests.thread.wait")

local function body(running, stopped)
	running:complete()
	wait.stop(stopped)
end

return body

