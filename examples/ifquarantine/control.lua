--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local device  = require("device")
local lunatik = require("lunatik")
local rcu     = require("rcu")
local runner  = require("lunatik.runner")
local stat    = require("linux.stat")

local FILTER      <const> = "examples/ifquarantine/filter"
local WATCH       <const> = "examples/ifquarantine/watch"
local KNOWN       <const> = "ifquarantine.known"
local QUARANTINED <const> = "ifquarantine.quarantined"
local quarantined         = rcu.table()   -- tostring(ifindex) -> true
local known               = rcu.table()   -- name -> ifindex
local lines

local function info(...)
	print("ifquarantine: " .. string.format(...))
end

local function list(name, idx)
	local state = quarantined[tostring(idx)] and "DROP" or "ALLOW"
	table.insert(lines, string.format("%s %d %s", name, idx, state))
end

local driver = {name = "ifquarantine", mode = stat.IRUGO | stat.IWUGO}

function driver:read(len, off)
	lines = {}
	rcu.foreach(known, list)
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

local function stop()
	runner.stop(FILTER)
	runner.stop(WATCH)
	lunatik._ENV[KNOWN] = nil
	lunatik._ENV[QUARANTINED] = nil
end

device.new(driver)
driver.sentinel = setmetatable({}, {__gc = stop})

lunatik._ENV[KNOWN] = known
lunatik._ENV[QUARANTINED] = quarantined
runner.run(WATCH, {context = "softirq"})

local runtimes = runner.run(FILTER, {context = "softirq", percpu = true})
runtimes:resume(quarantined)

