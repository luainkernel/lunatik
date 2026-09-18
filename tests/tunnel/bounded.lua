--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side relay for the bounded send test (see bounded.sh): plain.lua's
-- relay over a listener whose buffers the accepted sockets inherit, with a
-- transform that counts what it was handed.

local pair   = require("tests.tunnel.pair")
local tunnel = require("tunnel")
local sk     = require("linux.socket")

-- sk_clone_lock copies sk_rcvbuf, sk_sndbuf and the lock that keeps autotuning
-- off, so the path between the far ends holds tens of kilobytes rather than the
-- megabytes tcp_grow_window takes an unlocked one to
local BUFFER <const> = 4096

local listener = pair.listener()
listener:setsockopt(sk.sol.SOCKET, sk.so.RCVBUF, BUFFER)
listener:setsockopt(sk.sol.SOCKET, sk.so.SNDBUF, BUFFER)

local a
local counted = 0

-- a remainder put through the hook again on the next pass would count twice
local function count(data, from)
	if from == a then
		counted = counted + #data
	end
	return data
end

return function()
	local b
	a, b = pair.accept(listener)
	listener:close()
	if a == nil then
		return
	end
	tunnel.body(a, b, {transform = count})()
	print("tunnel bounded: the transform saw " .. counted .. " bytes")
end

