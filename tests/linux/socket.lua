--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.socket test (see run.sh).
--

local sk = require("linux.socket")
local test = require("util").test

-- the TCP_* option names, at the values uapi/linux/tcp.h gives them
local options = {
	NODELAY = 1, MAXSEG = 2, CORK = 3, KEEPIDLE = 4, KEEPINTVL = 5, KEEPCNT = 6,
	SYNCNT = 7, LINGER2 = 8, DEFER_ACCEPT = 9, WINDOW_CLAMP = 10, INFO = 11,
	QUICKACK = 12, CONGESTION = 13, MD5SIG = 14, THIN_LINEAR_TIMEOUTS = 16,
	THIN_DUPACK = 17, USER_TIMEOUT = 18, REPAIR = 19, REPAIR_QUEUE = 20,
	QUEUE_SEQ = 21, REPAIR_OPTIONS = 22, FASTOPEN = 23, TIMESTAMP = 24,
	NOTSENT_LOWAT = 25, CC_INFO = 26, SAVE_SYN = 27, SAVED_SYN = 28,
	REPAIR_WINDOW = 29, FASTOPEN_CONNECT = 30, ULP = 31, MD5SIG_EXT = 32,
	FASTOPEN_KEY = 33, FASTOPEN_NO_COOKIE = 34, ZEROCOPY_RECEIVE = 35, INQ = 36,
	TX_DELAY = 37,
}

-- absent from the header before 6.7 (the TCP-AO keys) and 6.10 (IS_MPTCP)
local recent = {
	AO_ADD_KEY = 38, AO_DEL_KEY = 39, AO_INFO = 40, AO_GET_KEYS = 41,
	AO_REPAIR = 42, IS_MPTCP = 43,
}

-- one name per family a bare TCP_ prefix takes, the TCP_INQ alias among them
local dropped = { "CM_INQ", "REPAIR_ON", "MSS_DEFAULT", "NLA_PAD", "CA_Open",
	"FLAG_SYN", "SEND_QUEUE", "MD5SIG_MAXKEYLEN" }

local levels = { SOCKET = 1, TCP = 6, TLS = 282 }

test("linux.socket.tcp carries every option name at its uapi value", function()
	for name, value in pairs(options) do
		assert(sk.tcp[name] == value, name .. ": " .. tostring(sk.tcp[name]))
	end
	for name, value in pairs(recent) do
		assert(sk.tcp[name] == nil or sk.tcp[name] == value, name .. ": " .. tostring(sk.tcp[name]))
	end
end)

test("every linux.socket.tcp entry is a positive option number, and none repeats", function()
	local named = {}
	for name, value in pairs(sk.tcp) do
		assert(value > 0, name .. " is not a positive option number: " .. value)
		assert(named[value] == nil, name .. " repeats the value of " .. tostring(named[value]))
		named[value] = name
	end
end)

test("linux.socket.tcp carries no alias or non-option constant", function()
	for _, name in ipairs(dropped) do
		assert(sk.tcp[name] == nil, name .. " is present")
	end
end)

test("linux.socket.sol carries the levels setsockopt routes on", function()
	for name, value in pairs(levels) do
		assert(sk.sol[name] == value, name .. ": " .. tostring(sk.sol[name]))
	end
end)

