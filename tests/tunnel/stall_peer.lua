--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side peer for the stalled destination test (see stall.sh).

local pair = require("tests.tunnel.pair")
local sk   = require("linux.socket")

local rep = string.rep

-- SO_RCVBUF and SO_SNDBUF lock the buffer against the kernel's autotuning, so
-- what the two far ends hold is this and not what the loopback path would grow to
local BUFFER <const> = 4096
local CHUNK  <const> = 65536
-- 16 MiB, past the widest the path can grow to: the relay's own receive buffer
-- is the deep one, since tcp_grow_window takes an unlocked one up to tcp_rmem's
-- maximum while nothing drains it
local LIMIT  <const> = 16 * 1024 * 1024

local source, sink = pair.tcp(), pair.tcp()
source:setsockopt(sk.sol.SOCKET, sk.so.SNDBUF, BUFFER)
-- the far end of the relay's send, and nothing here ever reads it: this is the stall
sink:setsockopt(sk.sol.SOCKET, sk.so.RCVBUF, BUFFER)

-- global, so the far ends outlive the chunk and the relay is still stalled
-- while the shell measures its stop
ends = {pair.connectpair(source, sink)}

local payload = rep("x", CHUNK)
local pushed = 0
local stalled = false
for _ = 1, LIMIT // CHUNK do
	local ok, sent = pcall(source.send, source, payload)
	if not ok or sent < CHUNK then
		pushed = pushed + (ok and sent or 0)
		stalled = true
		break
	end
	pushed = pushed + sent
end

assert(stalled, "the far ends took all " .. pushed .. " bytes, so nothing stalled")
print("tunnel stall: the destination stopped taking bytes after " .. pushed)

