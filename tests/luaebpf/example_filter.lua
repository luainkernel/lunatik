--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side fixture for the compiled SNI filter example (see example_filter.sh).

local linux   = require("linux")
local raw     = require("socket.raw")
local struct  = require("struct")
local packets = require("tests.luaebpf.packets")
local eth     = require("linux.eth")
local sk      = require("linux.socket")

local DEV     <const> = "filter0"  -- where the example attaches, and so where the tap listens
local PEER    <const> = "filter1"  -- and where the frames go on the wire
local BLOCKED <const> = "ebpf.io"  -- the name examples/filter/sni.lua blocks
local ALLOWED <const> = "pass.example"
local TIMEOUT <const> = 200000 -- microseconds a receive waits before it gives up
local DRAIN   <const> = 8      -- frames the tap reads before it stops looking
local MTU     <const> = 1500

local hosts = {BLOCKED, ALLOWED}

local timeval = struct(sk.layout.timeval)

local tap <close> = raw.bind(eth.ALL, linux.ifindex(DEV))
-- without this the drain below never returns on the run where a frame was dropped
tap:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT))

local wire <close> = raw.bind(eth.ALL, linux.ifindex(PEER))
for _, host in ipairs(hosts) do
	wire:send(packets.clienthello(host))
end

-- the tap matches on the host name's own bytes, so whatever else the machine puts on the pair is
-- ignored rather than silenced
local seen = {}
for _ = 1, DRAIN do
	local received, frame = pcall(tap.receive, tap, MTU)
	if not received then
		break
	end
	for _, host in ipairs(hosts) do
		if frame:find(host, 1, true) then
			seen[host] = true
		end
	end
end

for _, host in ipairs(hosts) do
	print("luaebpf filter: " .. host .. " " .. (seen[host] and "seen" or "absent"))
end

