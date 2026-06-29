--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Netlink request/response session. A session owns an `AF_NETLINK` socket and
-- the transaction discipline on it: `talk` and `dump` send one request and
-- drain its complete reply, raising on a kernel error reply (`NLMSG_ERROR`).
-- Protocol modules (rtnetlink, generic netlink) derive from this class.
-- All methods block and require a sleepable runtime.
--
-- @module netlink.session
-- @see socket
--

local socket  = require("socket")
local class   = require("class")
local message = require("netlink.message")
local struct  = require("struct")

local linux = require("linux")
local nl    = require("linux.netlink")
local sk    = require("linux.socket")

local insert = table.insert

local nlmsgerr      = struct(nl.layout.nlmsgerr)
local NLMSGERR_SIZE = nlmsgerr.size

local DONE, ERROR = nl.type.DONE, nl.type.ERROR
local MULTI       = nl.flag.MULTI

-- each receive takes one datagram and silently drops whatever exceeds the
-- buffer, so it must fit the largest dump datagram the kernel sends (~32K)
local BUFSIZE = 65536

---
-- Base class for netlink sessions.
-- @type session

---
-- Creates a new session object.
-- @function session:new
-- @tparam[opt] table o an initial object table.
-- @treturn session the new session object.
-- @see class
local session = class{}

local function isdone(msg)
	return msg.type == DONE or (msg.flags & MULTI) == 0
end

local function isack(msg)
	return msg.type == ERROR
end

-- Raises if any reply is an `NLMSG_ERROR` carrying a non-zero error code (an
-- error code of zero is the acknowledgment); returns the replies otherwise.
local function checked(messages)
	for _, msg in ipairs(messages) do
		if isack(msg) and #msg.body >= NLMSGERR_SIZE then
			local err = nlmsgerr:unpack(msg.body)
			if err ~= 0 then
				error(linux.errname(err), 0)
			end
		end
	end
	return messages
end

-- Receives datagrams until `last` matches a message (or a read comes back
-- empty), accumulating the parsed messages and raising on an error reply.
local function replies(sock, last)
	local messages = {}
	local done
	repeat
		local chunk = sock:receive(BUFSIZE)
		if #chunk == 0 then break end
		for _, msg in ipairs(message.parse(chunk)) do
			insert(messages, msg)
			if last(msg) then done = true end
		end
	until done
	return checked(messages)
end

-- Sends one request and drains its complete reply, up to the message that matches `last`.
local function transact(session, mtype, flags, payload, last)
	session:request(mtype, flags, payload)
	return replies(session.socket, last)
end

---
-- Creates a session backed by an `AF_NETLINK` socket of the class's `proto`.
-- @treturn session a new session object.
function session:__call()
	local o = self:new()
	o.socket = socket.new(sk.af.NETLINK, sk.sock.RAW, self.proto)
	o.sequence = 0
	return o
end

---
-- Sends one request (`NLM_F_REQUEST` plus `flags`) with a fresh sequence number, without waiting for a reply.
-- @tparam integer mtype message type.
-- @tparam integer flags additional NLM_F_* flags.
-- @tparam string payload the family header and attributes.
function session:request(mtype, flags, payload)
	self.sequence = self.sequence + 1
	self.socket:send(message.encode(mtype, nl.flag.REQUEST | flags, self.sequence, payload))
end

---
-- Sends a dump request and drains the multipart reply until `NLMSG_DONE`.
-- @tparam integer mtype message type.
-- @tparam string payload the family header and attributes.
-- @treturn table the parsed reply messages (the trailing `NLMSG_DONE` included; see `netlink.message.parse`).
-- @raise on a netlink error reply.
function session:dump(mtype, payload)
	return transact(self, mtype, nl.flag.DUMP, payload, isdone)
end

---
-- Sends a request with `NLM_F_ACK` and drains the reply up to the kernel
-- acknowledgment, keeping the socket in sync.
-- @tparam integer mtype message type.
-- @tparam[opt=0] integer flags extra NLM_F_* flags.
-- @tparam string payload the family header and attributes.
-- @treturn table the parsed reply messages (the trailing ack included).
-- @raise on a netlink error reply.
function session:talk(mtype, flags, payload)
	return transact(self, mtype, nl.flag.ACK | (flags or 0), payload, isack)
end

---
-- Closes the underlying socket.
function session:close()
	self.socket:close()
end

return session

