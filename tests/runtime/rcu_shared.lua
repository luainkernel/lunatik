--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Driver script for the rcu_shared regression test (see rcu_shared.sh).

local lunatik = require("lunatik")
local rcu     = require("rcu")

local rt = lunatik.runtime("tests/runtime/rcu_shared_recv")

local t = rcu.table(4)
t["answer"] = 42
lunatik._ENV["rcu_shared_test"] = t

rt:resume()

lunatik._ENV["rcu_shared_test"] = nil

