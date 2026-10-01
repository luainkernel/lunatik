--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the cycle_release test (see cycle_release.sh).

local rcu = require("rcu")

local function store(t, key, value)
	t[key] = value
end

local function pair()
	local a, b = rcu.table(), rcu.table()
	a.b = b
	pcall(store, b, "a", a)
end

pair()
collectgarbage() -- the handles pair() dropped: a holds b, and nothing holds a

