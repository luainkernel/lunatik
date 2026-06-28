--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Generic netlink (`NETLINK_GENERIC`) interface.
-- Create an instance with `genl()`, resolve a family name to its id, then
-- dispatch commands; close it when done. All methods block and require a
-- sleepable runtime.
--
-- @module netlink.genl
-- @see netlink
--

local netlink = require("netlink")
local message = require("netlink.message")

local nl   = require("linux.netlink")
local ctrl = require("linux.genl")

-- struct genlmsghdr: cmd(u8) version(u8) reserved(u16)
local GENL_HDR     = "<BBI2"
local GENL_HDRLEN  = 4
local GENL_VERSION = 1

local genl = {}

---
-- Constructor; sets up the metatable for OOP-style method dispatch.
-- @tparam[opt] table o initial object table.
-- @treturn table the new genl object.
function genl:new(o)
	o = o or {}
	self.__index = self
	self.__close = self.close
	return setmetatable(o, self)
end

---
-- Creates a new generic netlink instance backed by a `NETLINK_GENERIC` socket.
-- @treturn table a new genl object.
function genl:__call()
	local o = self:new()
	o.socket = netlink.new(nl.proto.GENERIC)
	return o
end

---
-- Closes the underlying socket.
function genl:close()
	self.socket:close()
end

local function encode(family_id, command, flags, payload)
	local header = string.pack(GENL_HDR, command, GENL_VERSION, 0)
	return message.encode(family_id, flags, message.seq(), header .. (payload or ""))
end

local function is_control(mtype)
	return mtype == nl.type.NOOP or mtype == nl.type.ERROR
		or mtype == nl.type.DONE or mtype == nl.type.OVERRUN
end

-- Parse a generic netlink response into a list of {cmd, attrs} messages,
-- skipping the standard control messages (ACK/DONE/...).
local function decode(buf)
	local msgs = {}
	for _, msg in ipairs(message.parse(buf)) do
		local body = msg.body
		if not is_control(msg.type) and #body >= GENL_HDRLEN then
			table.insert(msgs, {
				cmd = string.unpack("B", body),
				attrs = message.attrs(body, GENL_HDRLEN + 1),
			})
		end
	end
	return msgs
end

---
-- Resolves a generic netlink family name to its (dynamically assigned) id.
-- @tparam string name family name (e.g. `"nlctrl"`, `"nl80211"`).
-- @treturn integer the family id.
-- @raise if the family does not exist.
function genl:family(name)
	self.socket:send(encode(ctrl.id.CTRL, ctrl.cmd.GETFAMILY, nl.flag.REQUEST | nl.flag.ACK,
		message.attr(ctrl.attr.FAMILY_NAME, string.pack("z", name))))
	for _, msg in ipairs(decode(self.socket:recv(message.BUFSIZE))) do
		local fid = msg.attrs[ctrl.attr.FAMILY_ID]
		if fid then return string.unpack("<I2", fid) end
	end
	error("genl family not found: " .. name)
end

---
-- Sends a single generic netlink command and returns the raw response buffer.
-- @tparam integer family_id family id (from `family`).
-- @tparam integer command command number.
-- @tparam[opt=0] integer flags additional NLM_F_* flags.
-- @tparam[opt] string payload serialized attributes.
-- @treturn table list of `{cmd, attrs}` response messages.
-- @raise on netlink error.
function genl:call(family_id, command, flags, payload)
	self.socket:send(encode(family_id, command, nl.flag.REQUEST | nl.flag.ACK | (flags or 0), payload))
	local buf = self.socket:recv(message.BUFSIZE)
	message.check_error(buf)
	return decode(buf)
end

---
-- Sends a dump command and collects the full multipart response.
-- @tparam integer family_id family id (from `family`).
-- @tparam integer command command number.
-- @tparam[opt] string payload serialized attributes.
-- @treturn table list of `{cmd, attrs}` response messages.
-- @raise on netlink error.
function genl:dump(family_id, command, payload)
	self.socket:send(encode(family_id, command, nl.flag.REQUEST | nl.flag.DUMP, payload))
	local buf = message.recv_all(self.socket)
	message.check_error(buf)
	return decode(buf)
end

return setmetatable(genl, genl)

