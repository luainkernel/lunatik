--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Runtime for the notifier lock test (see lock.sh), resumed by tests/notifier/lock and spawned.

local lunatik  = require("lunatik")
local notifier = require("notifier")
local channel  = require("netlink.channel")
local net      = require("net")
local notify   = require("linux.notify")
local sk       = require("linux.socket")
local nl       = require("linux.netlink")
local probe    = require("tests.notifier.lock_probe")

local PLAIN    <const> = "tests/notifier/inside_resume"
local HELPER   <const> = "tests/notifier/lock_helper"
local FAMILY   <const> = "lunatik_lock"
local IP_TTL   <const> = 2 -- uapi/linux/in.h
local TTL      <const> = 64
local RCVBUF   <const> = 32768
local GROUP    <const> = 1
local LOOPBACK <const> = "127.0.0.1"
local DISCARD  <const> = 9
local DATAGRAM <const> = "notifier lock test"

local function nop()
	return notify.OK
end

local function bind()
	probe.open(sk.af.NETLINK, sk.sock.RAW, nl.proto.GENERIC):bind(0, GROUP)
end

local plain  = lunatik.runtime(PLAIN)
local set    = lunatik.percpu(PLAIN)
local packet = probe.open(sk.af.PACKET, sk.sock.RAW, 0) -- off the lock: loading the family module takes RTNL
local udp    = probe.open(sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP)

local function stopall()
	probe.report("close stop", plain.stop, plain)
	probe.report("close percpu stop", set.stop, set)
end

local sentinel = setmetatable({}, {__gc = stopall})
local early    = coroutine.wrap(probe.receive) -- made before the registration, and refused all the same
local block    = notifier.netdevice(nop)
probe.report("body request", probe.request)

local helpersentinel -- made after the helper: the close runs the newer finalizers first

-- the helper's body probes under this lock as it is created, and its code again once resumed
local function nest()
	local helper = lunatik.runtime(HELPER)
	helpersentinel = setmetatable({}, {__gc = function() probe.report("close helper stop", helper.stop, helper) end})
	helper:resume()
end

local function probeall()
	local _ = sentinel -- reachable until the close, whose finalizers stop the runtimes the probes could not
	if not probe.refused("receive", probe.receive) then -- a request the loaded build does not refuse can wedge the host
		return
	end
	probe.report("coroutine receive", early)
	probe.report("request", probe.request)
	probe.report("registration", notifier.netdevice, nop)
	probe.report("channel", channel.new, FAMILY)
	probe.report("unregistered new", probe.open, sk.af.UNSPEC, sk.sock.DGRAM, 0) -- no kernel registers AF_UNSPEC
	probe.report("registered new", probe.open, sk.af.INET, sk.sock.DGRAM, sk.ipproto.UDP)
	probe.report("bind", bind)
	probe.report("protocol option", udp.setsockopt, udp, sk.sol.IP, IP_TTL, TTL)
	probe.report("packet close", packet.close, packet)
	probe.report("stop", plain.stop, plain)
	probe.report("percpu stop", set.stop, set)
	probe.report("socket option", udp.setsockopt, udp, sk.sol.SOCKET, sk.so.RCVBUF, RCVBUF)
	probe.report("send", udp.send, udp, DATAGRAM, net.aton(LOOPBACK), DISCARD)
	probe.report("close", udp.close, udp)
	probe.report("nest", nest)
	block:stop()
	probe.report("stopped receive", probe.receive)
end

return probeall

