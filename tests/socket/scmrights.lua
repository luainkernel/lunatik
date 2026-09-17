--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the socket scmrights test (see scmrights.sh).

local socket = require("socket")
local struct = require("struct")
local sk     = require("linux.socket")

local timeval = struct(sk.layout.timeval)

local PATH     <const> = "/tmp/lunatik_scmrights.sock"
local GREETING <const> = "go"
local READMAX  <const> = 64
-- what the peer answers with, and how long a receive may wait for it
local ANSWER   <const> = "x"
local TIMEOUT  <const> = 5

-- a control buffer on an AF_UNIX read of SCM_RIGHTS reaches scm_detach_fds,
-- which warns and leaks the descriptors it then does not detach
local client = socket.new(sk.af.UNIX, sk.sock.STREAM, 0)
client:connect(PATH)
client:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(TIMEOUT, 0))
client:send(GREETING)

local data, record = client:receiverecord(READMAX)
client:close()
assert(data == ANSWER, "receiverecord returned " .. tostring(data))
assert(record == nil, "an AF_UNIX socket should report no record type, got " .. tostring(record))
print("socket scmrights: a receive of passed descriptors reports no record type")

