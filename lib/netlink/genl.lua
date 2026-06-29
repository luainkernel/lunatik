--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Generic netlink (`NETLINK_GENERIC`) interface. A `netlink.session`
-- specialization: create an instance with `genl()`, resolve a family name to
-- its id, then dispatch commands; close it when done. All methods block and
-- require a sleepable runtime.
--
-- @module netlink.genl
-- @see netlink.session
--

local session = require("netlink.session")
local message = require("netlink.message")
local struct  = require("struct")

local nl   = require("linux.netlink")
local ctrl = require("linux.genl")

local insert       = table.insert
local pack, unpack = string.pack, string.unpack

local genlmsghdr   = struct(ctrl.layout.genlmsghdr)
local GENL_HDRLEN  = genlmsghdr.size
-- genlmsghdr version stamped into requests; each family declares its own and
-- the genl core does not check it (no header constant exists for it)
local GENL_VERSION = 1

local NOOP, ERROR, DONE, OVERRUN = nl.type.NOOP, nl.type.ERROR, nl.type.DONE, nl.type.OVERRUN

---
-- Generic netlink session.
-- @type genl

---
-- Creates a new genl object.
-- @function genl:new
-- @tparam[opt] table o an initial object table.
-- @treturn genl the new genl object.
-- @see class
local genl = session:new{proto = nl.proto.GENERIC}

local function command(cmd, payload)
	return genlmsghdr:pack(cmd, GENL_VERSION, 0) .. (payload or "")
end

local function iscontrol(mtype)
	return mtype == NOOP or mtype == ERROR or mtype == DONE or mtype == OVERRUN
end

-- Decodes the session's reply messages into a list of {cmd, attrs}, skipping
-- the standard control messages (ACK/DONE/...). Attributes are taken right
-- after the genlmsghdr, so a family-specific header, if any, is left in them.
local function decode(messages)
	local msgs = {}
	for _, msg in ipairs(messages) do
		local body = msg.body
		if not iscontrol(msg.type) and #body >= GENL_HDRLEN then
			insert(msgs, {cmd = genlmsghdr:unpack(body), attrs = message.attrs(body, GENL_HDRLEN + 1)})
		end
	end
	return msgs
end

---
-- Sends a single generic netlink command and returns the decoded reply messages.
-- @tparam integer family_id family id (from `family`).
-- @tparam integer cmd command number.
-- @tparam[opt=0] integer flags additional NLM_F_* flags.
-- @tparam[opt] string payload serialized attributes.
-- @treturn table list of `{cmd, attrs}` response messages.
-- @raise on netlink error.
function genl:call(family_id, cmd, flags, payload)
	return decode(self:talk(family_id, flags, command(cmd, payload)))
end

---
-- Sends a dump command and collects the full multipart response.
-- @tparam integer family_id family id (from `family`).
-- @tparam integer cmd command number.
-- @tparam[opt] string payload serialized attributes.
-- @treturn table list of `{cmd, attrs}` response messages.
-- @raise on netlink error.
function genl:dump(family_id, cmd, payload)
	return decode(session.dump(self, family_id, command(cmd, payload)))
end

---
-- Resolves a generic netlink family name to its (dynamically assigned) id.
-- @tparam string name family name (e.g. `"nlctrl"`, `"nl80211"`).
-- @treturn integer the family id.
-- @raise if the family does not exist.
function genl:family(name)
	for _, msg in ipairs(self:call(ctrl.id.CTRL, ctrl.cmd.GETFAMILY, nil,
			message.attrs{[ctrl.attr.FAMILY_NAME] = pack("z", name)})) do
		local fid = msg.attrs[ctrl.attr.FAMILY_ID]
		if fid then return unpack("=I2", fid) end
	end
	error("genl family not found: " .. name)
end

return genl

