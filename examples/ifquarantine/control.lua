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
local notify   = require("linux.notify")
local stat     = require("linux.stat")

local filter      <const> = "examples/ifquarantine/filter"
local quarantined         = rcu.table()   -- tostring(ifindex) -> true
local known               = {}            -- name -> ifindex

local function info(...)
	print("ifquarantine: " .. string.format(...))
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

local function callback(event, name)
	if event == netdev.REGISTER then
		local ok, idx = pcall(linux.ifindex, name)
		if ok and idx then
			quarantine(name, idx)
		end
	elseif event == netdev.UNREGISTER then
		release(name)
		known[name] = nil
	end
	return notify.OK
end

local driver = {name = "ifquarantine", mode = stat.IRUGO | stat.IWUGO}

function driver:read()
	local lines = {}
	for name, idx in pairs(known) do
		local state = quarantined[tostring(idx)] and "DROP" or "ALLOW"
		table.insert(lines, string.format("%s %d %s", name, idx, state))
	end
	if #lines == 0 then
		return ""
	end
	return table.concat(lines, "\n") .. "\n"
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

local rt = runner.run(filter, "softirq")
rt:resume(quarantined)

driver.sentinel = setmetatable({}, {__gc = function()
	runner.stop(filter)
end})

notifier.netdevice(callback)

