--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Netlink message (de)serialization helpers shared by `netlink.rt` and
-- `netlink.genl`. Builds `nlmsghdr`/`nlattr` structures with `string.pack` and
-- parses received buffers into Lua tables.
-- @module netlink.message
--

local nl = require("linux.netlink")

local message = {}

-- struct nlmsghdr: len(u32) type(u16) flags(u16) seq(u32) pid(u32)
local NLMSG_HDR    = "<I4I2I2I4I4"
local NLMSG_HDRLEN = 16
-- struct nlattr: len(u16) type(u16)
local NLA_HDR    = "<I2I2"
local NLA_HDRLEN = 4

message.BUFSIZE = 65536

local function align(len)
	return (len + 3) & ~3
end

---
-- Builds a netlink attribute (`nlattr` plus padded value).
-- @tparam integer atype attribute type.
-- @tparam string value attribute payload.
-- @treturn string the serialized attribute.
function message.attr(atype, value)
	local len = NLA_HDRLEN + #value
	return string.pack(NLA_HDR, len, atype) .. value .. string.rep("\0", align(len) - len)
end

---
-- Builds a `u32` netlink attribute.
-- @tparam integer atype attribute type.
-- @tparam integer value attribute value.
-- @treturn string the serialized attribute.
function message.attr_u32(atype, value)
	return message.attr(atype, string.pack("<I4", value))
end

---
-- Builds a complete netlink message.
-- @tparam integer mtype message type.
-- @tparam integer flags NLM_F_* flags.
-- @tparam integer seq sequence number.
-- @tparam string payload family header and/or attributes.
-- @treturn string the serialized message.
function message.encode(mtype, flags, seq, payload)
	return string.pack(NLMSG_HDR, NLMSG_HDRLEN + #payload, mtype, flags, seq, 0) .. payload
end

---
-- Parses a buffer into a list of `{type, flags, body}` messages, where `body`
-- holds the bytes after the `nlmsghdr` (family header and attributes).
-- @tparam string buf received buffer.
-- @treturn table list of messages.
function message.parse(buf)
	local messages = {}
	local pos = 1
	while pos + NLMSG_HDRLEN - 1 <= #buf do
		local len, mtype, flags = string.unpack(NLMSG_HDR, buf, pos)
		if len < NLMSG_HDRLEN then break end
		table.insert(messages, {type = mtype, flags = flags,
			body = buf:sub(pos + NLMSG_HDRLEN, pos + len - 1)})
		pos = pos + align(len)
	end
	return messages
end

---
-- Parses the attributes in `body` starting at `offset` into a
-- `{[type] = value}` table.
-- @tparam string body message body.
-- @tparam integer offset first byte of the attribute area.
-- @treturn table attributes keyed by type.
function message.attrs(body, offset)
	local attrs = {}
	local pos = offset
	while pos + NLA_HDRLEN - 1 <= #body do
		local len, atype = string.unpack(NLA_HDR, body, pos)
		if len < NLA_HDRLEN then break end
		attrs[atype] = body:sub(pos + NLA_HDRLEN, pos + len - 1)
		pos = pos + align(len)
	end
	return attrs
end

local sequence = 0

---
-- Returns a fresh, monotonically increasing sequence number.
-- @treturn integer the sequence number.
function message.seq()
	sequence = sequence + 1
	return sequence
end

---
-- Receives a full multipart response, concatenating chunks until `NLMSG_DONE`
-- or a non-multipart message is seen.
-- @tparam netlink sock open netlink socket.
-- @treturn string the concatenated response buffer.
function message.recv_all(sock)
	local parts = {}
	local done
	repeat
		local chunk = sock:recv(message.BUFSIZE)
		table.insert(parts, chunk)
		for _, msg in ipairs(message.parse(chunk)) do
			if msg.type == nl.type.DONE or (msg.flags & nl.flag.MULTI) == 0 then
				done = true
				break
			end
		end
	until done
	return table.concat(parts)
end

---
-- Raises an error if any message in `buf` is an `NLMSG_ERROR` with a non-zero
-- error code.
-- @tparam string buf response buffer.
-- @raise on a netlink error.
function message.check_error(buf)
	for _, msg in ipairs(message.parse(buf)) do
		if msg.type == nl.type.ERROR then
			local err = string.unpack("<i4", msg.body)
			if err ~= 0 then
				error("netlink error " .. -err)
			end
		end
	end
end

return message

