--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local device   = require("device")
local linux    = require("linux")
local notifier = require("notifier")
local rcu      = require("rcu")
local runner   = require("lunatik.runner")
local netdev   = require("linux.netdev")
local stat     = require("linux.stat")

local filter      <const> = "examples/ifquarantine/filter"
local home        <const> = linux.netns() -- the namespace whose device indexes the filter reads
local quarantined         = rcu.table()   -- tostring(ifindex) -> true
local known               = {}            -- name -> ifindex

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

local function registered(name, idx, replayed)
	if replayed then
		record(name, idx)
	else
		quarantine(name, idx)
	end
end

local function renamed(name, idx)
	for old, known_idx in pairs(known) do
		if known_idx == idx then
			known[old] = nil
		end
	end
	known[name] = idx
end

local function unregistered(name, idx)
	quarantined[tostring(idx)] = nil
	known[name] = nil
	info("%s released", name)
end

local handlers = {[netdev.REGISTER] = registered, [netdev.CHANGENAME] = renamed, [netdev.UNREGISTER] = unregistered}

local function callback(event, name, netns, replayed, ifindex)
	local handler = handlers[event]
	if handler ~= nil and netns == home then -- an index of another namespace names another device here
		handler(name, ifindex, replayed)
	end
end

local driver = {name = "ifquarantine", mode = stat.IRUGO | stat.IWUGO}

function driver:read(len, off)
	local lines = {}
	for name, idx in pairs(known) do
		local state = quarantined[tostring(idx)] and "DROP" or "ALLOW"
		table.insert(lines, string.format("%s %d %s", name, idx, state))
	end
	if #lines == 0 then
		return ""
	end
	local text = table.concat(lines, "\n") .. "\n"
	return text:sub(off + 1, off + len)
end

function driver:write(buf)
	for cmd, name in string.gmatch(buf, "(%w+)=(%g+)") do
		local idx = known[name]
		if idx then
			if cmd == "allow" then
				quarantined[tostring(idx)] = nil
				info("%s allowed", name)
			elseif cmd == "deny" then
				quarantined[tostring(idx)] = true
				info("%s denied", name)
			end
		end
	end
end

device.new(driver)

local runtimes = runner.run(filter, {context = "softirq", percpu = true})

local function stopfilter()
	runner.stop(filter)
end

driver.sentinel = setmetatable({}, {__gc = stopfilter})

runtimes:resume(quarantined)

notifier.netdevice(callback)

