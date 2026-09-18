--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side peer for the kTLS tunnel test (see tls.sh).

local pair    = require("tests.tunnel.pair")
local session = require("tests.tls.session")
local tls     = require("tls")
local ltls    = require("linux.tls")

local TLS13   <const> = tls.version.TLS_1_3
local AES128  <const> = ltls.cipher.AES_GCM_128
-- a record the relay must read and drop, and the application data behind it,
-- which it must carry
local CONTROL <const> = "handshake bytes"
local AFTER   <const> = "past the control record"

-- global, so the far ends outlive the chunk and the shell closes them by
-- stopping this runtime
ends = {pair.tcp(), pair.tcp()}

local plain, keyed = ends[1], ends[2]
pair.connectpair(plain, keyed)
session.key(keyed, TLS13, AES128)

local data, record = pair.through(plain, keyed, pair.atob)
print("tunnel tls: B read " .. data .. " as record " .. tostring(record))
print("tunnel tls: A read " .. pair.through(keyed, plain, pair.btoa))

keyed:sendrecord(tls.record.HANDSHAKE, CONTROL)
keyed:send(AFTER)
print("tunnel tls: A read " .. plain:receiverecord(pair.readmax))

