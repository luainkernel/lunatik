--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the runtime/cstack test (see cstack.sh).
--

local lunatik   = require("lunatik")
local recursion = require("tests.runtime.cstack_recursion")

local SELF <const>    = "tests/runtime/cstack_self"
local RESUMED <const> = "tests/runtime/cstack_resumed"
local ERRERR <const>  = "error in error handling"

local OVERFLOW <const> = recursion.OVERFLOW

local function throughhandler()
	return select(2, xpcall(recursion.throughindex, recursion.throughindex))
end

recursion.report("pcall", OVERFLOW, recursion.throughpcall)
recursion.report("coroutine.wrap", OVERFLOW, recursion.throughwrap)
recursion.report("__index", OVERFLOW, recursion.throughindex)
recursion.report("rcu.foreach", OVERFLOW, recursion.throughforeach)
recursion.report("load", OVERFLOW, recursion.throughload)
recursion.report("collection", OVERFLOW, recursion.throughcollect)
recursion.report("runtime", OVERFLOW, lunatik.runtime, SELF)
recursion.report("message handler", ERRERR, throughhandler)

local resumed <close> = lunatik.runtime(RESUMED)
resumed:resume()

