--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side client for the examples/shared test (see shared.sh).

local socket = require("socket")
local net    = require("net")
local struct = require("struct")
local sk     = require("linux.socket")

local format = string.format

local HOST    <const> = "127.0.0.1"
local PORT    <const> = 90
local TIMEOUT <const> = 2
local LIMIT   <const> = 4096

local timeval = struct(sk.layout.timeval)
local cases = {}
local order = {"unset", "removed"}

local function connect()
	local client = socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
	-- an unanswered receive fails the case instead of parking its caller in D state
	client:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(TIMEOUT, 0))
	client:connect(net.aton(HOST), PORT)
	return client
end

-- a request gets a connection of its own: the daemon reads one line per receive, so two sent back to back are coalesced
local function set(request)
	local client = connect()
	client:send(request .. "\n")
	client:close()
end

local function get(key)
	local client = connect()
	client:send(key .. "\n")
	local reply = client:receive(LIMIT)
	client:close()
	return reply
end

function cases.unset()
	local reply = get("nokey")
	assert(reply == "\n", format("expected an empty line, got %d bytes", #reply))
end

function cases.removed()
	set("rm=x")
	set("rm=")
	local reply = get("rm")
	assert(reply == "\n", format("expected an empty line, got %d bytes", #reply))
end

for _, name in ipairs(order) do
	local ok, err = pcall(cases[name])
	print(format("shared example: %s %s", name, ok and "ok" or err))
end

