--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink stop test (see stop.sh).

local lunatik = require("lunatik")
local runner  = require("lunatik.runner")
local test    = require("tests.lib").test

local CHANNELS <const> = "tests/netlink/stop_channels"
local REFUSAL <const>  = "not allowed once the runtime is armed"

local function refused(channels)
	local ok, err = pcall(channels.resume, channels)
	assert(not ok, "an armed interrupt-context runtime stopped a channel")
	assert(err:match(REFUSAL), "an armed interrupt-context runtime raised something else: " .. err)
end

test("netlink: stop is accepted once a process runtime is armed", function()
	local channels <close> = lunatik.runtime(CHANNELS)
	channels:resume()
end)

test("netlink: stop is refused once a hardirq runtime is armed", function()
	local channels <close> = lunatik.runtime(CHANNELS, "hardirq")
	refused(channels)
end)

-- the runner keeps the channels' runtime under its name, which the cleanup stops
test("netlink: stop is refused once a softirq runtime is armed", function()
	refused(runner.run(CHANNELS, "softirq"))
end)

