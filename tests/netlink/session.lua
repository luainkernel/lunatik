--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netlink session test (see session.sh).

local session = require("netlink.session")
local message = require("netlink.message")
local struct  = require("struct")
local nl      = require("linux.netlink")

local nlmsgerr = struct(nl.layout.nlmsgerr)

local MTYPE  = 16 -- arbitrary message-type token
local ENOENT = -2

local function sock_send() end

local function sock_receive(self)
	self.i = self.i + 1
	return self.chunks[self.i]
end

local function fakesession(chunks)
	return session:new{sequence = 0, socket = {chunks = chunks, i = 0, send = sock_send, receive = sock_receive}}
end

local function errmsg(code)
	return message.encode(nl.type.ERROR, 0, 1, nlmsgerr:pack(code))
end

-- dump must terminate (not hang) on an empty read
assert(#fakesession{""}:dump(MTYPE, "") == 0, "dump on empty read should return no messages")
print("netlink session: dump empty-read ok")

-- talk drains the reply up to the ack and passes a zero error code; a data
-- message in the same datagram is kept, in order
local msgs = fakesession{message.encode(MTYPE, 0, 1, "data") .. errmsg(0)}:talk(MTYPE, nil, "")
assert(#msgs == 2 and msgs[1].type == MTYPE and msgs[2].type == nl.type.ERROR,
	"talk should return the data reply and the drained ack")
print("netlink session: talk drains the ack")

-- talk raises the bare symbolic error name on a kernel error reply
local s = fakesession{errmsg(ENOENT)}
local ok, err = pcall(s.talk, s, MTYPE, nil, "")
assert(not ok and err == "ENOENT", "talk should raise ENOENT, got " .. tostring(err))
print("netlink session: talk raises on error")

