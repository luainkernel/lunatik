--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the opt_guards regression tests (see opt_guards.sh).

local lunatik = require("lunatik")
local data     = require("data")
local rcu      = require("rcu")

local function assert_error(fn, pattern)
	local ok, err = pcall(fn)
	assert(not ok, "expected error but got none")
	assert(err:find(pattern), "unexpected error: " .. tostring(err))
end

local function assert_ok(fn)
	local ok, err = pcall(fn)
	assert(ok, "unexpected error: " .. tostring(err))
end

local recv = lunatik.runtime("tests/runtime/opt_guards_recv")

-- SINGLE via resume: must be rejected (use a disposable runtime — SINGLE error kills the coroutine)
assert_error(function()
	local tmp = lunatik.runtime("tests/runtime/opt_guards_recv")
	tmp:resume(data.new(4, "single"))
end, "cannot share SINGLE object")

-- SINGLE via _ENV: must be rejected
assert_error(function()
	lunatik._ENV["opt_guard_test"] = data.new(4, "single")
end, "cannot share SINGLE object")

-- MONITOR via resume: must succeed
assert_ok(function()
	local d = data.new(4)
	recv:resume(d)
end)

-- MONITOR explicit mode via resume: must succeed
assert_ok(function()
	local d = data.new(4, "shared")
	recv:resume(d)
end)

-- MONITOR via _ENV: must succeed
assert_ok(function()
	local d = data.new(4)
	lunatik._ENV["opt_guard_monitor"] = d
	lunatik._ENV["opt_guard_monitor"] = nil
end)

-- NONE via resume: must succeed
assert_ok(function()
	local t = rcu.table(4)
	recv:resume(t)
end)

-- NONE via _ENV: must succeed
assert_ok(function()
	local t = rcu.table(4)
	lunatik._ENV["opt_guard_none"] = t
	lunatik._ENV["opt_guard_none"] = nil
end)

-- MONITOR object passed via resume multiple times: refcount must remain stable
assert_ok(function()
	local d = data.new(4)
	recv:resume(d)
	recv:resume(d)
	recv:resume(d)
end)

-- Invalid mode: must error
assert_error(function()
	data.new(4, "invalid")
end, "invalid option")

