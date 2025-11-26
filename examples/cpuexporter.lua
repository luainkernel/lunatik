--
-- SPDX-FileCopyrightText: (c) 2025 Enderson Maia <endersonmaia@gmail.com>
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

local lunatik = require("lunatik")
local thread  = require("thread")
local socket  = require("socket")
local unix    = require("socket.unix")
local linux   = require("linux")
local cpu     = require("cpu")

local shouldstop = thread.shouldstop
local sock = socket.sock

local server = unix.bind("/tmp/cpuexporter.sock", "STREAM")
server:listen()

local last_stats = {}

-- Scale integer to decimal with high precision
-- Converts a ratio (value/total) to percentage format with 16 decimal places
local function to_percent_float(value, total)
	if total == 0 then
		return "0.0000000000000000"
	end

	local int_part = (value * 100) // total
	local remainder = (value * 100) % total
	local frac_high = (remainder * 100000000) // total
	local remainder2 = (remainder * 100000000) % total
	local frac_low = (remainder2 * 100000000) // total

	return string.format("%d.%08d%08d", int_part, frac_high, frac_low)
end

-- Helper function to sum all stats values in a table
-- Note: guest and guest_nice are already included in user and nice respectively
-- according to the Linux kernel documentation, so we must exclude them from the total
local function _sum_cpu_stats(stats)
	local sum = 0
	for key, value in pairs(stats) do
		-- Skip guest times as they're already included in user/nice
		if not (key == "guest" or key == "guest_nice") then
			sum = sum + value
		end
	end
	return sum
end

-- returns cpu_stats table
local function cpu_stats()
	--TODO: add cpu-total with accumulated values for all cpus
	local cpu_stats = {}
	cpu.foreach_online(function(cpu_id)
		cpu_stats[cpu_id] = {}
		cpu_stats[cpu_id] = cpu.stats(cpu_id)
		cpu_stats[cpu_id]._total = _sum_cpu_stats(cpu_stats[cpu_id])
	end)
	return cpu_stats
end

-- returns cpu_usage (%) table
local function cpu_usage()
	local usage = {}
	local current_stats = cpu_stats()

	for cpu_id, _ in pairs(current_stats) do
		local total_delta = current_stats[cpu_id]._total - (last_stats[cpu_id]._total or 0)
		local guest_delta = current_stats[cpu_id].guest - (last_stats[cpu_id].guest or 0)
		local guest_nice_delta = current_stats[cpu_id].guest_nice - (last_stats[cpu_id].guest_nice or 0)

		usage[cpu_id] = {}
		for metric, value in pairs(current_stats[cpu_id]) do
			-- Skip _total metric
			if metric ~= "_total" then
				local metric_delta = value - (last_stats[cpu_id][metric] or 0)

				if metric == "user" then
					metric_delta = metric_delta - guest_delta
				elseif metric == "nice" then
					metric_delta = metric_delta - guest_nice_delta
				end
				usage[cpu_id][metric] = to_percent_float(metric_delta, total_delta)
			end
		end
	end

	last_stats = current_stats
	return usage
end

local function cpu_metrics()
	local metrics = ""
	local ts_ms = linux.time() // 1000  -- Convert to milliseconds (FIXME: note sure if this conversion is necessary)
	local usage_data = cpu_usage()  -- Call once and store the result

	-- Collect all unique metric names from the first available CPU
	local cpu_metric_names = {}
	for _, cpu_metrics in pairs(usage_data) do
		for key, _ in pairs(cpu_metrics) do
			cpu_metric_names[key] = true
		end
		break  -- Only need one CPU to get all metric names
	end

	-- Output grouped by metric name
	for metric, _ in pairs(cpu_metric_names) do
		metrics = metrics .. string.format('# TYPE cpu_usage_%s gauge\n', metric)
		for cpu_id, cpu_metrics in pairs(usage_data) do
			local value = cpu_metrics[metric] or "0"
			metrics = metrics .. string.format('cpu_usage_%s{cpu="cpu%d"} %s %d\n',
				metric, cpu_id, value, ts_ms)
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
last_stats = cpu_stats()

local function daemon()
	print("cpud [daemon]: started")
	while (not shouldstop()) do
		local ok, session = pcall(server.accept, server, sock.NONBLOCK)
		if ok then
			local ok, err = pcall(handle_client, session)
			if not ok then
				print("cpud [daemon]: error handling client: " .. tostring(err))
			end
			session:close()
		elseif session == "EAGAIN" then
			linux.schedule(100)
		end
	end
	print("cpud [daemon]: stopped")
end

return daemon

