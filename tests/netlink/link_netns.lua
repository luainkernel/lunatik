--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink link_netns test (see link_netns.sh).

local netlink = require("netlink")
local socket  = require("socket")
local signal  = require("signal")
local linux   = require("linux")
local sk      = require("linux.socket")
local nl      = require("linux.netlink")
local pids    = require("tests.netns_pid")

local DEV     <const> = "lunatikns0"
local PROTO   <const> = 32  -- MAX_LINKS: past every netlink protocol
local TRIES   <const> = 50
local WAIT    <const> = 100 -- ms between tries
local SETTLE  <const> = 1000 -- ms for the namespace's teardown to run, had the socket not held it

local function listed(link)
	local names = {}
	for _, l in ipairs(link:list()) do
		names[l.name] = true
	end
	return names
end

local function reachable(pid)
	local ok, session = pcall(netlink.rt.link, pid)
	if ok then
		session:close()
	end
	return ok
end

do
	local link <close> = netlink.rt.link()
	local names = listed(link)
	assert(names.lo and not names[DEV], "initial namespace should list lo and not " .. DEV)
	print("netlink link_netns: initial namespace lists lo, not " .. DEV)
end

local ok, session = pcall(netlink.rt.link, pids.holder)
if not ok and session == "EOPNOTSUPP" then
	print("netlink link_netns: a task's namespace is refused: EOPNOTSUPP")
	return
end
assert(ok, "the holder's namespace should be reached, got " .. tostring(session))
local link <close> = session
local names = listed(link)
assert(names.lo and names[DEV], "the holder's namespace should list lo and " .. DEV)
print("netlink link_netns: holder's namespace lists " .. DEV)

local ok, err = pcall(netlink.rt.link, pids.reaped)
assert(not ok and err == "ESRCH", "a reaped pid should raise ESRCH, got " .. tostring(err))
print("netlink link_netns: reaped pid raises ESRCH")

ok, err = pcall(socket.new, sk.af.NETLINK, sk.sock.RAW, nl.proto.ROUTE, 0)
assert(not ok and err:match("out of bounds"), "pid 0 should be out of bounds, got " .. tostring(err))
ok, err = pcall(socket.new, sk.af.NETLINK, sk.sock.RAW, PROTO, pids.holder)
assert(not ok and err == "EPROTONOSUPPORT", "a protocol past MAX_LINKS should raise, got " .. tostring(err))
print("netlink link_netns: pid out of range and refused socket raise")

signal.kill(pids.holder)
local tries = 0
while reachable(pids.holder) do
	tries = tries + 1
	assert(tries < TRIES, "the holder did not exit")
	linux.schedule(WAIT)
end
linux.schedule(SETTLE)
assert(listed(link)[DEV], DEV .. " not listed after the holder exited")
print("netlink link_netns: " .. DEV .. " listed after the holder exited")

