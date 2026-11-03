--
-- SPDX-FileCopyrightText: (c) 2025-2026 Enderson Maia <endersonmaia@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local thread  = require("thread")
local unix    = require("socket.unix")
local linux   = require("linux")
local cpu     = require("cpu")

local shouldstop = thread.shouldstop
local NONBLOCK   = require("linux.socket").sock.NONBLOCK

local server = unix.stream("\0cpuexporter")
server:bind()
server:listen()

local last_stats = {}
local last_total_stats = {}

-- Converts a ratio (metric/total) to a percentage with 2 decimal places: remainder * 100 fits where total * 100 does
local function format_percentage(metric, total)
	if total == 0 then
		return "0.00"
	end

	local int_part = (metric * 100) // total
	local remainder = (metric * 100) % total
	local frac = (remainder * 100) // total

	return string.format("%d.%02d", int_part, frac)
end

-- CPU states only: guest and guest_nice are counted in user and nice, forceidle on top of the task that ran
local function sum_stats(stats)
	return stats.user + stats.nice + stats.system + stats.idle + stats.iowait + stats.irq + stats.softirq + stats.steal
end

-- returns per cpu stats, total_stats tables
local function cpu_stats()
	--TODO: add cpu-total with accumulated values for all cpus
	local stats = {}
	local total_stats = {}
	for id in cpu.online() do
		stats[id] = cpu.stats(id)
		total_stats[id] = sum_stats(stats[id])
	end
	return stats, total_stats
end

-- returns cpu_usage (%) table
local function cpu_usage()
	local usage = {}
	local current_stats, current_total_stats = cpu_stats()

	for cpu_id, _ in pairs(current_stats) do
		local total_delta = current_total_stats[cpu_id] - (last_total_stats[cpu_id] or 0)
		local guest_delta = current_stats[cpu_id].guest - (last_stats[cpu_id].guest or 0)
		local guest_nice_delta = current_stats[cpu_id].guest_nice - (last_stats[cpu_id].guest_nice or 0)

		usage[cpu_id] = {}
		for metric, value in pairs(current_stats[cpu_id]) do
			local metric_delta = value - (last_stats[cpu_id][metric] or 0)

			-- the kernel adds a guest tick to user before guest, and cpu.stats can read between the two adds
			if metric == "user" then
				metric_delta = math.max(metric_delta - guest_delta, 0)
			elseif metric == "nice" then
				metric_delta = math.max(metric_delta - guest_nice_delta, 0)
			end
			usage[cpu_id][metric] = format_percentage(metric_delta, total_delta)
		end
	end

	last_stats = current_stats
	last_total_stats = current_total_stats
	return usage
end

local function cpu_metrics()
	local metrics = ""
	local ts_ms = linux.time() // 1000000  -- convert nanoseconds to milliseconds
	local usage_data = cpu_usage()  -- Call once and store the result

	-- Collect all unique metric names from the first available CPU
	local cpu_metric_names = {}
	for _, percents in pairs(usage_data) do
		for key, _ in pairs(percents) do
			cpu_metric_names[key] = true
		end
		break  -- Only need one CPU to get all metric names
	end

	-- Output grouped by metric name
	for metric, _ in pairs(cpu_metric_names) do
		metrics = metrics .. string.format('# TYPE cpu_usage_%s gauge\n', metric)
		for cpu_id, percents in pairs(usage_data) do
			metrics = metrics .. string.format('cpu_usage_%s{cpu="cpu%d"} %s %d\n',
				metric, cpu_id, percents[metric], ts_ms)
		end
	end

	return metrics
end

local function handle_client(session)
	-- Read the request
	local request, err = session:receive(1024)
	if not request then
		error(err)
	end

	-- Check if this is an HTTP request
	local method, path, http_version = string.match(request, "^(%w+)%s+([^%s]+)%s+(HTTP/%d%.%d)")

	if http_version then
		-- This is an HTTP request, validate it
		if method ~= "GET" then
			session:send("HTTP/1.1 405 Method Not Allowed\r\n\r\n")
			error("Method not allowed: " .. tostring(method))
		end

		if path ~= "/metrics" then
			session:send("HTTP/1.1 404 Not Found\r\n\r\n")
			error("Path not found: " .. tostring(path))
		end

		-- Send HTTP response headers
		session:send("HTTP/1.1 200 OK\r\n")
		session:send("Content-Type: text/plain; version=0.0.4\r\n")
		session:send("\r\n")
	end

	-- Send metrics (works for both HTTP and plain connections like socat)
	session:send(cpu_metrics())
end

-- Initial sample
last_stats, last_total_stats = cpu_stats()

local function daemon()
	print("cpud [daemon]: started")
	while (not shouldstop()) do
		local session = server:accept(NONBLOCK)
		if session then
			local ok, err = pcall(handle_client, session)
			if not ok then
				print("cpud [daemon]: error handling client: " .. tostring(err))
			end
			session:close()
		else
			linux.schedule(100)
		end
	end
	print("cpud [daemon]: stopped")
end

return daemon

