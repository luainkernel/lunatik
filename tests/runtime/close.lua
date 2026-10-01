--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the close test (see close.sh).

local lunatik  = require("lunatik")
local device   = require("device")
local fsnotify = require("fsnotify")
local notifier = require("notifier")
local fs       = require("linux.fs")
local test     = require("tests.lib").test

local DEVICE <const> = "lunatik_close"
local PROBE  <const> = "tests/runtime/close_probe"
local MARKED <const> = "/tmp"

local function stops(handle)
	local class = getmetatable(handle)
	assert(class.__close == class.stop, class.__name .. "'s __close is not its stop")
end

local function scope(handle)
	local held <close> = handle
end

local function ignore()
end

test("device: a to-be-closed device is stopped, through the stop it holds as __close", function()
	local dev = device.new({name = DEVICE})
	stops(dev)
	scope(dev)
	device.new({name = DEVICE}):stop() -- device_create refuses a name a device still holds
end)

test("notifier: a to-be-closed notifier is stopped, through the stop it holds as __close", function()
	local block = notifier.netdevice(ignore)
	stops(block)
	scope(block)
	block:stop()
end)

test("fsnotify: a to-be-closed watch is stopped, through the stop it holds as __close", function()
	local watch = fsnotify.watch(ignore)
	stops(watch)
	scope(watch)
	local ok, err = pcall(watch.mark, watch, MARKED, fs.OPEN)
	assert(not ok and tostring(err):match("closed object"), "a to-be-closed watch still marks")
end)

test("probe: a to-be-closed probe is stopped, through the stop it holds as __close", function()
	local runtime <close> = lunatik.runtime(PROBE, "hardirq") -- raises what the probe's body asserts
end)

