--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the kTLS plaintext relay test (see loopback.sh).

local session = require("tests.tls.session")
local tls     = require("tls")
local ltls    = require("linux.tls")

local TLS12   <const> = tls.version.TLS_1_2
local TLS13   <const> = tls.version.TLS_1_3
local AES128  <const> = ltls.cipher.AES_GCM_128
local CHACHA  <const> = ltls.cipher.CHACHA20_POLY1305
local PAYLOAD <const> = "the quick brown fox"
-- one record read in two calls: 4 bytes, then the remaining 12
local SPLIT   <const> = "0123456789abcdef"
local HEAD    <const> = 4
-- wider than any record this test sends, so a read is cut short only where the
-- case means it to be
local READMAX <const> = 64

-- one plaintext across the session, with the record type the kernel reports
local function relay(from, to, message)
	from:send(message)
	local data, record = to:receiverecord(READMAX)
	assert(data == message, "the peer read " .. tostring(data))
	assert(record == tls.record.DATA, "expected application data, got " .. tostring(record))
end

local client, server = session.connectpair()
session.install(client, server, TLS13, AES128)
relay(client, server, PAYLOAD)
print("tls loopback: a TLS 1.3 session carries plaintext")

-- the same session the other way: both directions are keyed, not only the one
-- that was written first
relay(server, client, PAYLOAD)
session.closepair(client, server)
print("tls loopback: the reverse direction carries plaintext too")

-- the other version validate_crypto_info accepts
client, server = session.connectpair()
session.install(client, server, TLS12, AES128)
relay(client, server, PAYLOAD)
relay(server, client, PAYLOAD)
session.closepair(client, server)
print("tls loopback: a TLS 1.2 session carries plaintext")

-- the zero-salt cipher: its AEAD is allocated at install time, so a kernel that
-- does not build it answers ENOENT there and the case skips on that errno
client, server = session.connectpair()
local ok, err = pcall(session.install, client, server, TLS13, CHACHA)
if ok then
	relay(client, server, PAYLOAD)
	relay(server, client, PAYLOAD)
end
session.closepair(client, server)
if ok then
	print("tls loopback: the zero-salt cipher carries plaintext")
else
	print("tls loopback: the zero-salt cipher is unavailable (" .. tostring(err) .. ")")
end

-- a record read in two calls: process_rx_list attaches the cmsg to the second
-- read as well, so the type is reported on the remainder too
client, server = session.connectpair()
session.install(client, server, TLS13, AES128)
client:send(SPLIT)
local head, headrecord = server:receiverecord(HEAD)
local tail, tailrecord = server:receiverecord(READMAX)
session.closepair(client, server)
assert(head == SPLIT:sub(1, HEAD), "the first read returned " .. tostring(head))
assert(headrecord == tls.record.DATA, "the first read reported " .. tostring(headrecord))
assert(tail == SPLIT:sub(HEAD + 1), "the second read returned " .. tostring(tail))
assert(tailrecord == tls.record.DATA, "the second read reported " .. tostring(tailrecord))
print("tls loopback: a record read in two calls reports its type twice")

