--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket_data regression test (see socket_data.sh).

local socket = require("socket")
local net    = require("net")
local data   = require("data")

local af   = socket.af
local sock = socket.sock
local ip   = socket.ipproto
local PORT = 19876
local MSG  = "hello socket data!"
local SIZE = #MSG

local s = socket.new(af.INET, sock.DGRAM, ip.UDP)
s:bind(net.aton("127.0.0.1"), PORT)

local sbuf = data.new(SIZE, "single")
sbuf:setstring(0, MSG)
local rbuf = data.new(SIZE, "single")

-- data → data
s:send(sbuf, net.aton("127.0.0.1"), PORT)
local n = s:receive(rbuf)
assert(n == SIZE, "data→data: expected " .. SIZE .. " bytes, got " .. tostring(n))
assert(rbuf:getstring(0, n) == MSG, "data→data: content mismatch")

-- string → data
s:send(MSG, net.aton("127.0.0.1"), PORT)
local n2 = s:receive(rbuf)
assert(n2 == SIZE, "string→data: expected " .. SIZE .. " bytes, got " .. tostring(n2))
assert(rbuf:getstring(0, n2) == MSG, "string→data: content mismatch")

-- data → string
s:send(sbuf, net.aton("127.0.0.1"), PORT)
local str = s:receive(SIZE)
assert(str == MSG, "data→string: content mismatch")

s:close()

