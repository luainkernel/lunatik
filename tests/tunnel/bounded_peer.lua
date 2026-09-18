--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side peer for the bounded send test (see bounded.sh).

local pair = require("tests.tunnel.pair")
local sk   = require("linux.socket")

local rep = string.rep

-- the far end of the relay's send, and nothing here reads it until the push is
-- over: this is what makes every send of the relay's a short one
local BUFFER <const> = 4096
local CHUNK  <const> = 8192
-- past what the locked buffers on both sides of the relay can hold
local LIMIT  <const> = 1024 * 1024

local source, sink = pair.tcp(), pair.tcp()
source:setsockopt(sk.sol.SOCKET, sk.so.SNDBUF, BUFFER)
sink:setsockopt(sk.sol.SOCKET, sk.so.RCVBUF, BUFFER)

-- global, so the far ends outlive the chunk and the shell closes them by
-- stopping this runtime
ends = {pair.connectpair(source, sink)}

local payload = rep("x", CHUNK)
local pushed = 0
local stalled = false
for _ = 1, LIMIT // CHUNK do
	local ok, sent = pcall(source.send, source, payload)
	pushed = pushed + (ok and sent or 0)
	if not ok or sent < CHUNK then
		stalled = true
		break
	end
end

assert(stalled, "the far ends took all " .. pushed .. " bytes, so nothing stalled")
print("tunnel bounded: the destination stopped taking bytes after " .. pushed)

-- the relay is now inside a send it cannot finish on every pass; the bound is
-- what ends that pass, and the reverse direction is what it ends it for
local ok, back = pcall(pair.through, sink, source, pair.btoa)
print("tunnel bounded: A read " .. (ok and back or "nothing (" .. tostring(back) .. ")"))

-- draining the sink lets the relay deliver the remainders its short writes left
-- pending, so the byte count that comes out of B is the one that went into A
local drained = 0
while drained < pushed do
	local more, data = pcall(sink.receiverecord, sink, CHUNK)
	if not more or #data == 0 then
		break
	end
	drained = drained + #data
end
print("tunnel bounded: B read " .. drained .. " of " .. pushed)

