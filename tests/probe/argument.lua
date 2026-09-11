--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe argument test (see argument.sh).

local probe = require("probe")

local COUNT <const> = 8191 -- the size argument.sh reads

local stale
local done = false

local function pass(what)
	print("probe argument: " .. what)
end

local function pre(_, _, argument)
	if done then
		return
	end

	if stale ~= nil then
		done = true
		if not pcall(stale, 2) then
			pass("stale")
		end
		return
	end

	if argument(2) ~= COUNT then
		return
	end

	pass("read")
	if not pcall(argument, -1) then
		pass("bounds")
	end
	stale = argument
end

probe.new("vfs_read", {pre = pre})

