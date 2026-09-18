--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the handshake options test (see options.sh).

local socket    = require("socket")
local net       = require("net")
local data      = require("data")
local handshake = require("handshake")
local sk        = require("linux.socket")

local find = string.find

local LOCALHOST  <const> = "127.0.0.1"
-- ta_timeout_ms is an unsigned int, and a wider one would reach it truncated
local MAXTIMEOUT <const> = 0xffffffff
-- key_serial_t is a signed 32-bit id, and a wider one would reach the copy loop truncated
local MAXSERIAL  <const> = 0x7fffffff

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
end

local server = tcpsocket()
server:bind(net.aton(LOCALHOST), 0)
server:listen()
local _, port = server:getsockname()

local client = tcpsocket()
client:connect(net.aton(LOCALHOST), port)

local ok, err = pcall(handshake.server, client, {})
assert(not ok and find(err, "no anonymous server handshake", 1, true),
	"a server hello with no credentials should be refused")
print("handshake options: a server hello needs credentials")

-- tls_client_hello_psk refuses an empty identity list before it allocates, and
-- is the only path here that answers EINVAL: the reading that the psk arm ran
ok, err = pcall(handshake.client, client, {peerids = {}})
assert(not ok and err == "EINVAL", "an empty peerids list should raise EINVAL, got " .. tostring(err))
print("handshake options: an empty peerids list selects the psk arm")

ok, err = pcall(handshake.client, client, {peerids = {1, 2, 3, 4, 5, 6}})
assert(not ok and find(err, "too many peerids", 1, true), "six identities should be refused")
print("handshake options: six identities are refused")

ok, err = pcall(handshake.client, client, {cert = 1})
assert(not ok and find(err, "cert and privkey go together", 1, true),
	"a cert with no privkey should be refused")
print("handshake options: a cert with no privkey is refused")

ok, err = pcall(handshake.client, client, {peerids = {1}, cert = 1, privkey = 1})
assert(not ok and find(err, "peerids and cert name different handshakes", 1, true),
	"peerids beside a cert should be refused")
print("handshake options: peerids beside a cert is refused")

ok, err = pcall(handshake.client, client, {peerids = {1, "two"}})
assert(not ok and find(err, "peerids holds a non-integer", 1, true),
	"a peerid that is not a number should be refused")
print("handshake options: a peerid that is not a number is refused")

ok, err = pcall(handshake.client, client, {peerids = {MAXSERIAL + 1}})
assert(not ok and find(err, "out of bounds", 1, true),
	"a peerid wider than the kernel's field should be refused")
print("handshake options: a peerid wider than the kernel's field is refused")

ok, err = pcall(handshake.client, client, {timeout = "soon"})
assert(not ok and find(err, "bad field 'timeout'", 1, true), "a timeout that is not a number should be refused")
print("handshake options: a field of the wrong type is refused")

ok, err = pcall(handshake.client, client, {timeout = MAXTIMEOUT + 1})
assert(not ok and find(err, "out of bounds", 1, true), "a timeout wider than the kernel's field should be refused")
print("handshake options: a timeout wider than the kernel's field is refused")

-- luasocket_openfile checks the class before it reads the private, and the private before it attaches
ok, err = pcall(handshake.client, data.new(8))
assert(not ok and find(err, "socket expected, got data", 1, true),
	"an object of another class should be refused")
print("handshake options: an object of another class is refused")

local gone = tcpsocket()
gone:close()
ok, err = pcall(handshake.client, gone)
assert(not ok and find(err, "null pointer dereference", 1, true), "a closed socket should be refused")
print("handshake options: a closed socket is refused")

client:close()
server:close()

