--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Regression: register_netdevice_notifier synchronously replays NETDEV_REGISTER
-- (and NETDEV_UP) for each existing netdev under the new notifier_block. When
-- `notifier.netdevice(cb)` is called directly from script init, the replay
-- fires luanotifier_call while runtime->private was still NULL under the old
-- "defer private until after pcall" design, causing lua_gettop(NULL) via the
-- islocked sentinel path in lunatik_handle. The framework now wraps L with a
-- readiness flag published under the runtime lock: sync handlers dispatched
-- during register_fn find a valid L, while async handlers (kprobes) still see
-- -ENXIO via !lunatik_isready(runtime) until init finishes.
--

local notifier = require("notifier")
local seen = 0

local function cb(event, name)
	seen = seen + 1
	return 0
end

local n = notifier.netdevice(cb)
assert(seen >= 1, "expected at least one replayed NETDEV event during init (got " .. seen .. ")")
n:stop()

