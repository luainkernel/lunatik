--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink message test (see message.sh).

local message = require("netlink.message")

-- arbitrary header and attribute-type tokens for the pure round-trip
local MTYPE, FLAGS, SEQ = 16, 5, 1
local U32ATTR, STRATTR  = 4, 3

local payload = message.attrs{[U32ATTR] = 0x01020304, [STRATTR] = "eth0\0"}
local buf = message.encode(MTYPE, FLAGS, SEQ, payload)

local msgs = message.parse(buf)
assert(#msgs == 1 and msgs[1].type == MTYPE and msgs[1].flags == FLAGS, "message header round-trip failed")

local attrs = message.attrs(msgs[1].body, 1)
assert(string.unpack("=I4", attrs[U32ATTR]) == 0x01020304, "u32 attribute round-trip failed")
assert(string.unpack("z", attrs[STRATTR]) == "eth0", "string attribute round-trip failed")
print("netlink message: round-trip ok")

-- malformed wire data stops cleanly (never raises); invalid input raises
assert(#message.parse("") == 0 and #message.parse(buf:sub(1, #buf - 2)) == 0,
	"truncated buffer should parse to no messages")
assert(message.attrs{} == "" and next(message.attrs("", 1)) == nil, "empty attribute set should round-trip empty")
assert(not pcall(message.attrs, {[U32ATTR] = -1}), "non-u32 number should raise")
print("netlink message: edge cases ok")

