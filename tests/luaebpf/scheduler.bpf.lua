--
-- SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Program file of the scheduler case (see scheduler.sh): the minimal sched_ext
-- scheduler bpf.scx writes, a name and an init callback that returns 0 to let it
-- load. Its struct_ops map is the one `lunatik run` registers with no device,
-- which the C schedulers of tests/scx never make the compiler write.

local scx = require("bpf.scx")

return scx.scheduler{
	name = "luaebpfmin",
	init = function() return 0 end,
}

