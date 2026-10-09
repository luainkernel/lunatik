--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local linux    = require("linux")
local lunatik  = require("lunatik")
local notifier = require("notifier")
local netdev   = require("linux.netdev").cmd
local notify   = require("linux.notify")

local home        <const> = linux.netns() -- the namespace linux.ifindex resolves a name in
local known               = lunatik._ENV["ifquarantine.known"]       -- name -> ifindex
local quarantined         = lunatik._ENV["ifquarantine.quarantined"] -- tostring(ifindex) -> true
local loading             = true

local function info(...)
	print("ifquarantine: " .. string.format(...))
end

local function record(name, idx)
	known[name] = idx
	info("%s (ifindex=%d) already present", name, idx)
end

local function quarantine(name, idx)
	known[name] = idx
	quarantined[tostring(idx)] = true
	info("%s (ifindex=%d) quarantined", name, idx)
end

local function release(name)
	local idx = known[name]
	if idx then
		quarantined[tostring(idx)] = nil
		info("%s released", name)
	end
end

local function callback(event, name, netns)
	if netns ~= home then -- a device of another namespace: its name resolves onto the wrong one here
		return notify.OK
	end
	if event == netdev.REGISTER then
		local idx = linux.ifindex(name)
		if idx then
			if loading then
				record(name, idx)
			else
				quarantine(name, idx)
			end
		end
	elseif event == netdev.UNREGISTER then
		release(name)
		known[name] = nil
	end
	return notify.OK
end

notifier.netdevice(callback)
loading = false

