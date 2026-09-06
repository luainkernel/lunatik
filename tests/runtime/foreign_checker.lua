--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the checker matrix test (see foreign_checker.sh).

local lunatik    = require("lunatik")
local data       = require("data")
local fifo       = require("fifo")
local completion = require("completion")
local set        = require("set")
local crypto     = require("crypto")
local thread     = require("thread")
local rcu        = require("rcu")
local test       = require("util").test

local SCRIPT <const> = "tests/runtime/resume_shared_recv"

local cases = {
	{name = "data",         object = data.new(8),                 foreign = fifo.new(16), method = "getuint8",   args = {0},
		got = "fifo"},
	{name = "fifo",         object = fifo.new(16),                foreign = data.new(8),  method = "push",       args = {"x"}},
	{name = "completion",   object = completion.new(),            foreign = data.new(8),  method = "complete",   args = {}},
	{name = "set",          object = set.new{"a"},                foreign = data.new(8),  method = "has",        args = {"a"}},
	{name = "crypto_shash", object = crypto.shash("sha256"),  foreign = data.new(8),  method = "digestsize", args = {}},
	{name = "task",         object = thread.current():task(),     foreign = data.new(8),  method = "pid",        args = {}},
	{name = "runtime",      object = lunatik.runtime(SCRIPT),     foreign = data.new(8),  method = "resume",     args = {1}},
}

local function refused(what, method, object, ...)
	local ok, err = pcall(method, object, ...)
	assert(not ok, what .. " was accepted")
	return err
end

for _, case in ipairs(cases) do
	local method = getmetatable(case.object)[case.method]
	local what = case.name .. ":" .. case.method
	test(what .. " refuses an object of another class", function()
		local err = refused(what, method, case.foreign, table.unpack(case.args))
		assert(err:match(case.name .. " expected, got " .. (case.got or "data")), what .. " raised something else: " .. err)
	end)
	test(what .. " refuses a value that is no object", function()
		local err = refused(what, method, nil, table.unpack(case.args))
		assert(err:match("invalid object"), what .. " raised something else: " .. err)
	end)
	test(what .. " refuses a userdata of another library", function()
		local err = refused(what, method, io.stdout, table.unpack(case.args))
		assert(err:match("invalid object"), what .. " raised something else: " .. err)
	end)
end

test("fifo:push refuses a closed fifo", function()
	local queue = fifo.new(16)
	queue:close()
	local err = refused("fifo:push", getmetatable(queue).push, queue, "x")
	assert(err:match("null pointer"), "push raised something else: " .. err)
end)

test("rcu.map refuses nil", function()
	local err = refused("rcu.map", rcu.map, nil, function() end)
	assert(err:match("invalid object"), "rcu.map raised something else: " .. err)
end)

test("runtime:resume refuses a closed runtime", function()
	local runtime = lunatik.runtime(SCRIPT)
	runtime:stop()
	local err = refused("runtime:resume", getmetatable(runtime).resume, runtime, 1)
	assert(err:match("null pointer"), "resume raised something else: " .. err)
end)

for _, case in ipairs(cases) do
	if case.name == "runtime" then case.object:stop() end
end

