--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Drops a child from an atomic writer, for the deferred test's drivers (see deferred.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")

local WRITER <const> = "tests/runtime/deferred_writer"

local contexts = {"softirq", "hardirq"}

local deferred = {}

function deferred.drop(child)
	for _, context in ipairs(contexts) do
		local entries = rcu.table()
		entries.child = lunatik.runtime(child)
		collectgarbage() -- the handle: the entry holds the child's only reference
		local writer <close> = lunatik.runtime(WRITER, context)
		writer:resume(entries)
	end
end

return deferred

