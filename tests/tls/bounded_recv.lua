--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the kTLS bounded receive test (see bounded_recv.sh).

local session = require("tests.tls.session")
local linux   = require("linux")
local struct  = require("struct")
local tls     = require("tls")
local sk      = require("linux.socket")
local ltls    = require("linux.tls")

local timeval = struct(sk.layout.timeval)

local TLS13   <const> = tls.version.TLS_1_3
local AES128  <const> = ltls.cipher.AES_GCM_128
local PAYLOAD <const> = "after the wait"
local READMAX <const> = 64

-- linux.time counts nanoseconds; the timeval codec takes microseconds
local US <const> = 1000
local MS <const> = 1000000

local TIMEOUT <const> = 100 * MS
-- what a receive that never waits is allowed to take, and what a receive that
-- waits for its timeout must not exceed
local PROMPT  <const> = 50 * MS
local PATIENT <const> = 2000 * MS

-- a receive that must raise, and how long the raise took
local function timedfail(sock, flags)
	local started = linux.time()
	local ok, err = pcall(sock.receiverecord, sock, READMAX, flags)
	local elapsed = linux.difftime(linux.time(), started)
	assert(not ok, "a receive with nothing to read should raise")
	assert(err == "EAGAIN", "expected EAGAIN, got " .. tostring(err))
	return elapsed
end

local client, server = session.connectpair()
session.install(client, server, TLS13, AES128)

-- tls_rx_rec_wait takes sock_rcvtimeo(sk, nonblock) and answers EAGAIN at
-- if (!timeo), which MSG_DONTWAIT reaches without waiting
local elapsed = timedfail(server, sk.msg.DONTWAIT)
assert(elapsed < PROMPT, "a non-blocking receive took " .. elapsed // MS .. " ms")
print("tls bounded: a non-blocking receive returned in " .. elapsed // MS .. " ms")

-- the same wait bounded by SO_RCVTIMEO instead: the receive blocks and still
-- returns, which is what a kernel thread rests on, since tls_rx_rec_wait never
-- checks kthread_should_stop
server:setsockopt(sk.sol.SOCKET, sk.so.RCVTIMEO_NEW, timeval:pack(0, TIMEOUT // US))
elapsed = timedfail(server)
assert(elapsed > PROMPT, "a bounded receive returned in " .. elapsed // MS .. " ms, as if it never waited")
assert(elapsed < PATIENT, "a bounded receive took " .. elapsed // MS .. " ms")
print("tls bounded: a receive bounded by SO_RCVTIMEO returned in " .. elapsed // MS .. " ms")

-- the timeout bounds the wait and does not spend the session
client:send(PAYLOAD)
local data, record = server:receiverecord(READMAX)
session.closepair(client, server)
assert(data == PAYLOAD, "the session read " .. tostring(data) .. " after its timeout")
assert(record == tls.record.DATA, "expected application data, got " .. tostring(record))
print("tls bounded: the session still carries plaintext after a timeout")

