--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink message test (see message.sh).
-- Pure round-trip: build a message with attributes and parse it back.

local message = require("netlink.message")

local payload = message.attr_u32(4, 0x01020304) .. message.attr(3, "eth0\0")
local buf = message.encode(16, 5, message.seq(), payload)

local msgs = message.parse(buf)
assert(#msgs == 1 and msgs[1].type == 16, "message header round-trip failed")

local attrs = message.attrs(msgs[1].body, 1)
assert(string.unpack("<I4", attrs[4]) == 0x01020304, "u32 attribute round-trip failed")
assert(string.unpack("z", attrs[3]) == "eth0", "string attribute round-trip failed")
print("netlink message: round-trip ok")

