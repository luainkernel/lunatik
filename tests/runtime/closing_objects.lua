--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Closing script for the closing test (see closing.sh).

local lunatik = require("lunatik")

local CHILD <const> = "tests/runtime/closing_child"
local CASE  <const> = "tests/runtime/closing.case"
local KEY   <const> = "tests/runtime/closing.child"

local env = lunatik._ENV
local held = {}
local setups = {}
local closes = {}

-- in the order closing.lua numbers them
local names = {"clone", "resume", "runtime", "percpu"}

function setups.clone()
	env[KEY] = lunatik.runtime(CHILD)
end

function closes.clone()
	held.taken = env[KEY]
	env[KEY] = nil
end

function setups.resume()
	held.child = lunatik.runtime(CHILD)
	held.echo = lunatik.runtime(CHILD)
end

function closes.resume()
	held.taken = held.echo:resume(held.child)
	held.echo:stop()
end

function closes.runtime()
	held.taken = lunatik.runtime(CHILD)
end

function closes.percpu()
	held.taken = lunatik.percpu(CHILD)
end

local name = names[env[CASE]]
local setup = setups[name]
if setup ~= nil then
	setup()
end

sentinel = setmetatable({}, {__gc = closes[name]})

