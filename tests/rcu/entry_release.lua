--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the entry_release test (see entry_release.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")
local data    = require("data")

local CHILD <const> = "tests/rcu/entry_release_child"
local SIZE  <const> = 8

local entries = rcu.table()

entries.removed = lunatik.runtime(CHILD)
entries.replaced = lunatik.runtime(CHILD)
collectgarbage() -- the handles the assignments left: each entry holds its child's only reference

entries.removed = nil -- the child closes here, on this task, once the table's lock is dropped
entries.replaced = data.new(SIZE)

