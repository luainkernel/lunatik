--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The recursions through C the runtime/cstack test runs (see cstack.sh).
--

local rcu = require("rcu")

local wrap = coroutine.wrap

local NESTING <const> = 1000

local recursion = {}

recursion.OVERFLOW = "C stack overflow"

local entries = rcu.table(1)
entries.entry = true

local function deeper(proxy, key)
	return proxy[key]
end

local proxy = setmetatable({}, {__index = deeper})

local littered, finalized = 0, 0

local function finalize()
	finalized = finalized + 1
end

local finalizable = {__gc = finalize}

local function litter()
	setmetatable({}, finalizable)
	littered = littered + 1
end

local function collectdeeper(collector, key)
	litter()
	collectgarbage()
	return collector[key]
end

local collector = setmetatable({}, {__index = collectdeeper})

local function collect()
	return collector.key
end

function recursion.throughpcall()
	return select(2, pcall(recursion.throughpcall))
end

function recursion.throughwrap()
	wrap(recursion.throughwrap)()
end

function recursion.throughindex()
	return proxy.key
end

function recursion.throughforeach()
	rcu.foreach(entries, recursion.throughforeach)
end

function recursion.throughload()
	assert(load("return " .. ("("):rep(NESTING) .. "0" .. (")"):rep(NESTING)))
end

function recursion.throughcollect()
	local _, err = pcall(collect)
	collectgarbage()
	collectgarbage()
	error(finalized == littered and err or ("%d of %d finalizers ran"):format(finalized, littered))
end

function recursion.report(route, expected, f, ...)
	local _, err = pcall(f, ...)
	local message = tostring(err)
	print(("cstack test: %s %s"):format(route, message:find(expected, 1, true) and "raises" or message))
end

return recursion

