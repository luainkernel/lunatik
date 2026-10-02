--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Probes the notifier lock test (see lock.sh) runs from lock_holder and from lock_helper.

local socket = require("socket")
local rt     = require("netlink.rt")
local sk     = require("linux.socket")
local nl     = require("linux.netlink")

local insert = table.insert

local PREFIX  <const> = "notifier lock test: "
local REFUSAL <const> = "not allowed under the lock of a runtime with a netdevice notifier"
local RCVBUF  <const> = 32768

local probe = {}

-- closed with the runtime, off its lock: collected under it, a release that takes RTNL would run there
local kept = {}

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
function probe.report(what, fn, ...)
	local ok, err = pcall(fn, ...)
	local verdict = ok and "accepted" or tostring(err):gsub("^.-:%d+: ", ""):gsub("%s+$", "")
	print(PREFIX .. what .. " " .. verdict)
	return verdict
end

function probe.refused(what, fn, ...)
	return probe.report(what, fn, ...) == REFUSAL
end

function probe.open(family, type, protocol)
	local sock = socket.new(family, type, protocol)
	insert(kept, sock)
	return sock
end

function probe.request()
	local link <close> = rt.link()
	link:list()
end

function probe.receive()
	probe.open(sk.af.NETLINK, sk.sock.RAW, nl.proto.ROUTE):receive(RCVBUF, sk.msg.DONTWAIT)
end

return probe

