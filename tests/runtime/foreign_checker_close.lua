--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the close case of the checker matrix test (see foreign_checker.sh).

local lunatik = require("lunatik")
local fifo    = require("fifo")
local crypto  = require("crypto")
local device  = require("device")
local stat    = require("linux.stat")
local test    = require("tests.lib").test

local RUNTIME <const> = "tests/runtime/resume_shared_recv"
local BODY    <const> = "tests/runtime/my_body"
local DEVICE  <const> = "foreign_checker"

local function empty()
	return ""
end

local spawned = lunatik._ENV.threads[BODY]
local driver = {name = DEVICE, mode = stat.IRUGO, read = empty}
local dev = device.new(driver)
local runtime = lunatik.runtime(RUNTIME)
local queue = fifo.new(16)

local closes = {
	{name = "fifo:close", method = getmetatable(queue).close, refusal = "object of another class",
		objects = {thread = spawned, device = dev, runtime = runtime}},
	{name = "runtime:stop", method = getmetatable(runtime).stop, refusal = "lunatik%%.runtime expected, got %s",
		objects = {thread = spawned, device = dev, fifo = queue}},
}

local attempts = {}
for _, close in ipairs(closes) do
	for class, object in pairs(close.objects) do
		local ok, err = pcall(close.method, object)
		table.insert(attempts, {what = close.name .. " on a " .. class, ok = ok, err = tostring(err),
			refusal = close.refusal:format(class)})
	end
end

local digest = crypto.shash("sha256")
do
	local scoped <close> = digest
end
local digested, digesterr = pcall(digest.digestsize, digest)

local tasked = pcall(spawned.task, spawned)
local devstopped, deverr = pcall(dev.stop, dev)
local stopped, stoperr = pcall(runtime.stop, runtime)
queue:close()

for _, attempt in ipairs(attempts) do
	test(attempt.what .. " is refused", function()
		assert(not attempt.ok, attempt.what .. " was accepted")
		assert(attempt.err:match(attempt.refusal), attempt.what .. " raised something else: " .. attempt.err)
	end)
end

test("a refused close leaves the thread, the device and the runtime to their own methods", function()
	assert(tasked, "thread:task failed after the refusals")
	assert(devstopped, "device:stop failed after the refusals: " .. tostring(deverr))
	assert(stopped, "runtime:stop failed after the refusals: " .. tostring(stoperr))
end)

test("crypto.shash's __close closes its own object", function()
	assert(not digested, "digestsize was accepted after the close")
	assert(digesterr:match("closed object"), "digestsize raised something else: " .. digesterr)
end)

