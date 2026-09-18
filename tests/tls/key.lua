--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the kTLS keying test (see key.sh).

local socket = require("socket")
local net    = require("net")
local tls    = require("tls")
local sk     = require("linux.socket")
local ltls   = require("linux.tls")

local rep = string.rep

local LOCALHOST <const> = "127.0.0.1"
local ULPNAME   <const> = "tls"

local TLS12 <const> = tls.version.TLS_1_2
local TLS13 <const> = tls.version.TLS_1_3

-- a version the kernel does not implement, which validate_crypto_info refuses
local BADVERSION <const> = 0x0305

local AES128 <const> = ltls.cipher.AES_GCM_128
local AES256 <const> = ltls.cipher.AES_GCM_256
local CHACHA <const> = ltls.cipher.CHACHA20_POLY1305
-- the uapi header carries no ARIA before 6.1
local ARIA   <const> = ltls.cipher.ARIA_GCM_128

local names = {}
for name, cipher in pairs(ltls.cipher) do names[cipher] = name end

-- fixed vectors of exactly the sizes the cipher wants: no record is ever
-- encrypted here, so only the lengths reach the kernel's notice
local function payload(version, cipher)
	local name = names[cipher]
	local saltsize = ltls.size[name .. "_SALT_SIZE"]
	-- nil rather than "" where the cipher has no salt, as a script would write it
	local salt = saltsize > 0 and rep("\3", saltsize) or nil
	return tls.pack(version, cipher, rep("\1", ltls.size[name .. "_IV_SIZE"]),
		rep("\2", ltls.size[name .. "_KEY_SIZE"]), salt, rep("\4", ltls.size[name .. "_REC_SEQ_SIZE"]))
end

local function tcpsocket()
	return socket.new(sk.af.INET, sk.sock.STREAM, sk.ipproto.TCP)
end

-- a client connected to a listener bound to port 0, so the test takes no fixed
-- port from the host
local function connectpair()
	local server = tcpsocket()
	server:bind(net.aton(LOCALHOST), 0)
	server:listen()
	local _, port = server:getsockname()
	local client = tcpsocket()
	client:connect(net.aton(LOCALHOST), port)
	return client, server
end

-- the same pair with the tls ULP attached, which tls_init grants only to a
-- socket that is already ESTABLISHED
local function ulppair()
	local client, server = connectpair()
	client:setsockopt(sk.sol.TCP, sk.tcp.ULP, ULPNAME)
	return client, server
end

local function closepair(client, server)
	client:close()
	server:close()
end

local function install(sock, direction, blob)
	sock:setsockopt(sk.sol.TLS, direction, blob)
end

local function installboth(sock, blob)
	install(sock, ltls.TX, blob)
	install(sock, ltls.RX, blob)
end

local aes128 = payload(TLS13, AES128)

-- with no ULP on the socket, SOL_TLS falls through tcp_setsockopt to ip_setsockopt
local client, server = connectpair()
local ok, err = pcall(install, client, ltls.TX, aes128)
closepair(client, server)
assert(not ok and err == "ENOPROTOOPT", "keying with no ULP should raise ENOPROTOOPT, got " .. tostring(err))
print("tls key: an unkeyed socket refuses SOL_TLS")

-- both directions of one session install, and the answer below is the only
-- reading Lua has that the first install took
client, server = ulppair()
installboth(client, aes128)
print("tls key: TX and RX installed")

-- from 6.14 do_tls_setsockopt_conf lets a keyed TLS 1.3 direction re-key with
-- the same version and cipher instead of refusing, so both answers are the
-- kernel's and the case names the one it gave
local txok, txerr = pcall(install, client, ltls.TX, aes128)
local rxok, rxerr = pcall(install, client, ltls.RX, aes128)
closepair(client, server)
assert(txok or txerr == "EBUSY", "a second TX install should raise EBUSY or re-key, got " .. tostring(txerr))
assert(rxok or rxerr == "EBUSY", "a second RX install should raise EBUSY or re-key, got " .. tostring(rxerr))
print("tls key: a second TLS 1.3 install " .. (txok and "re-keyed" or "was refused with EBUSY"))

-- the other version validate_crypto_info accepts
local aes128_12 = payload(TLS12, AES128)
client, server = ulppair()
install(client, ltls.TX, aes128_12)
print("tls key: TLS 1.2 installed")

-- the entry check above refuses every version but 1.3, so on a TLS 1.2
-- direction the refusal holds on every kernel
ok, err = pcall(install, client, ltls.TX, aes128_12)
closepair(client, server)
assert(not ok and err == "EBUSY", "a second TLS 1.2 install should raise EBUSY, got " .. tostring(err))
print("tls key: a TLS 1.2 direction installs once")

-- the zero-salt cipher: its AEAD is allocated at install time, so a kernel that
-- does not build it answers ENOENT here and nowhere else
client, server = ulppair()
ok, err = pcall(installboth, client, payload(TLS13, CHACHA))
closepair(client, server)
if ok then
	print("tls key: the zero-salt cipher installed")
else
	print("tls key: the zero-salt cipher is unavailable (" .. tostring(err) .. ")")
end

-- do_tls_setsockopt_conf takes the cipher's struct size and no other length
client, server = ulppair()
ok, err = pcall(install, client, ltls.TX, aes128:sub(1, #aes128 - 1))
closepair(client, server)
assert(not ok and err == "EINVAL", "a blob one byte short should raise EINVAL, got " .. tostring(err))
print("tls key: a short blob refused")

-- judging the version is the kernel's, which is why tls.pack does not
client, server = ulppair()
ok, err = pcall(install, client, ltls.TX, payload(BADVERSION, AES128))
closepair(client, server)
assert(not ok and err == "EINVAL", "an unimplemented version should raise EINVAL, got " .. tostring(err))
print("tls key: an unimplemented version refused")

-- the two directions of a session carry one version and one cipher
client, server = ulppair()
install(client, ltls.TX, aes128)
ok, err = pcall(install, client, ltls.RX, payload(TLS13, AES256))
closepair(client, server)
assert(not ok and err == "EINVAL", "a second cipher on RX should raise EINVAL, got " .. tostring(err))
print("tls key: the directions must agree")

-- ARIA is the one cipher validate_crypto_info ties to a version, and it judges
-- before the AEAD is allocated, so the refusal shows on a kernel building none
if ARIA == nil then
	print("tls key: ARIA is absent from this kernel's uapi")
else
	client, server = ulppair()
	ok, err = pcall(install, client, ltls.TX, payload(TLS13, ARIA))
	closepair(client, server)
	assert(not ok and err == "EINVAL", "ARIA under TLS 1.3 should raise EINVAL, got " .. tostring(err))
	print("tls key: ARIA is refused outside TLS 1.2")
end

