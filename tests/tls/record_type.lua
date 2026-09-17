--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the kTLS control record test (see record_type.sh).

local session = require("tests.tls.session")
local tls     = require("tls")
local ltls    = require("linux.tls")

local char = string.char

local TLS13   <const> = tls.version.TLS_1_3
local AES128  <const> = ltls.cipher.AES_GCM_128
local PAYLOAD <const> = "application data"
-- the level and the description of a close_notify, as RFC 8446 numbers them
local WARNING <const> = 1
local NOTIFY  <const> = 0
-- wider than any record this test sends, so no case is cut short by the length
local READMAX <const> = 64

local function keyedpair()
	local client, server = session.connectpair()
	session.install(client, server, TLS13, AES128)
	return client, server
end

-- the TX cmsg is what makes the peer read an alert: without it tls_sw_sendmsg
-- leaves the record at application data
local client, server = keyedpair()
client:sendrecord(tls.record.ALERT, char(WARNING, NOTIFY))
local data, record = server:receiverecord(READMAX)
session.closepair(client, server)
assert(record == tls.record.ALERT, "the peer should read an alert, got " .. tostring(record))
assert(data == char(WARNING, NOTIFY), "the alert carried " .. #data .. " bytes")
print("tls record: a sent alert arrives as an alert")

-- the helper emits what the kernel's own tls_alert_send does
client, server = keyedpair()
local sent = tls.close_notify(client)
data, record = server:receiverecord(READMAX)
session.closepair(client, server)
assert(sent == 2, "close_notify sent " .. tostring(sent) .. " bytes")
assert(record == tls.record.ALERT, "close_notify should arrive as an alert, got " .. tostring(record))
assert(data:byte(1) == WARNING and data:byte(2) == NOTIFY,
	"close_notify carried " .. tostring(data:byte(1)) .. "," .. tostring(data:byte(2)))
print("tls record: close_notify is a warning-level alert")

-- the gap this closes: tls_record_content_type fails the read with EIO when a
-- record that is not application data meets a caller with no control buffer
client, server = keyedpair()
tls.close_notify(client)
local ok, err = pcall(server.receive, server, READMAX)
session.closepair(client, server)
assert(not ok and err == "EIO", "a plain receive of an alert should raise EIO, got " .. tostring(err))
print("tls record: a plain receive of a control record raises EIO")

-- and that EIO is about control records, not about keyed sockets
client, server = keyedpair()
client:send(PAYLOAD)
local plain = server:receive(READMAX)
session.closepair(client, server)
assert(plain == PAYLOAD, "a plain receive of application data returned " .. tostring(plain))
print("tls record: a plain receive of application data returns it")

