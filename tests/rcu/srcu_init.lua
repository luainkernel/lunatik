--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the srcu_init test (see srcu_init.sh).

local rcu = require("rcu")

local t = rcu.table()
t.key = true
t.key = false

