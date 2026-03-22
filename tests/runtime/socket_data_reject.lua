--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket_data_reject regression test (see socket_data_reject.sh).

local socket = require("socket")
local net    = require("net")
local data   = require("data")

local af   = socket.af
local sock = socket.sock
local ip   = socket.ipproto
local PORT = 19877
local SIZE = 16

local s = socket.new(af.INET, sock.DGRAM, ip.UDP)
s:bind(net.aton("127.0.0.1"), PORT)

-- rejection: wrong-type userdata (socket instead of data)
local ok, err = pcall(function() s:send(s, net.aton("127.0.0.1"), PORT) end)
assert(not ok and err:find("bad argument"), "send: wrong type not rejected: " .. tostring(err))

local ok2, err2 = pcall(function() s:receive(s) end)
assert(not ok2 and err2:find("bad argument"), "receive: wrong type not rejected: " .. tostring(err2))

-- rejection: non-SINGLE (shared) data
local shared = data.new(SIZE, "shared")

local ok3, err3 = pcall(function() s:send(shared, net.aton("127.0.0.1"), PORT) end)
assert(not ok3 and err3:find("bad argument"), "send: non-SINGLE data not rejected: " .. tostring(err3))

local ok4, err4 = pcall(function() s:receive(shared) end)
assert(not ok4 and err4:find("bad argument"), "receive: non-SINGLE data not rejected: " .. tostring(err4))

s:close()

