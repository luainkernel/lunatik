--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Helper runtime for the notifier lock test (see lock.sh), created and resumed by tests/notifier/lock_holder.

local probe = require("tests.notifier.lock_probe")

local function probeall(where)
	if probe.refused(where .. " receive", probe.receive) then -- an unrefused request can wedge the host
		probe.report(where .. " request", probe.request)
	end
end

local function resumed()
	probeall("helper resume")
end

probeall("helper body")

return resumed

