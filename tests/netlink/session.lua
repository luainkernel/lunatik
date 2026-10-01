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

local function sock_send(self, msg)
	self.sent = msg
end

local function sock_receive(self)
	self.i = self.i + 1
	return self.chunks[self.i] or ""
end

local function fakesession(chunks)
	return session:new{sequence = 0, socket = {chunks = chunks, i = 0, send = sock_send, receive = sock_receive}}
end

local function errmsg(code)
	return message.encode(nl.type.ERROR, 0, 1, nlmsgerr:pack(code))
end

local function sent(fake)
	return message.parse(fake.socket.sent)[1].flags
end

-- dump must terminate (not hang) on an empty read
assert(#fakesession{""}:dump(MTYPE, "") == 0, "dump on empty read should return no messages")
print("netlink session: dump empty-read ok")

-- dump must drain a MULTI reply that never sends DONE down to the empty read
local drained = fakesession{message.encode(MTYPE, nl.flag.MULTI, 1, "data")}:dump(MTYPE, "")
assert(#drained == 1 and drained[1].type == MTYPE, "dump should drain a MULTI reply to the empty read")
print("netlink session: dump drains a MULTI reply ok")

-- talk drains the reply up to the ack and passes a zero error code; a data
-- message in the same datagram is kept, in order
local msgs = fakesession{message.encode(MTYPE, 0, 1, "data") .. errmsg(0)}:talk(MTYPE, "")
assert(#msgs == 2 and msgs[1].type == MTYPE and msgs[2].type == nl.type.ERROR,
	"talk should return the data reply and the drained ack")
print("netlink session: talk drains the ack")

-- talk raises the bare symbolic error name on a kernel error reply
local s = fakesession{errmsg(ENOENT)}
local ok, err = pcall(s.talk, s, MTYPE, "")
assert(not ok and err == "ENOENT", "talk should raise ENOENT, got " .. tostring(err))
print("netlink session: talk raises on error")

-- request without flags sends NLM_F_REQUEST alone; talk adds NLM_F_ACK to the flags it is given
s = fakesession{}
s:request(MTYPE, "")
assert(sent(s) == nl.flag.REQUEST, "request without flags should send NLM_F_REQUEST alone")
s = fakesession{errmsg(0)}
s:talk(MTYPE, "", nl.flag.CREATE)
assert(sent(s) == nl.flag.REQUEST | nl.flag.ACK | nl.flag.CREATE, "talk should send the flags it is given")
print("netlink session: flags last and optional")

