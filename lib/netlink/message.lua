--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Netlink wire codec shared by the netlink modules. Builds `nlmsghdr`/`nlattr`
-- structures via the `struct` codec and parses received buffers into Lua
-- tables.
-- @module netlink.message
--

local nl     = require("linux.netlink")
local struct = require("struct")

local insert, concat = table.insert, table.concat
local pack, rep      = string.pack, string.rep

local message = {}

local nlmsghdr     = struct(nl.layout.nlmsghdr)
local nlattr       = struct(nl.layout.nlattr)
local NLMSG_HDRLEN = nlmsghdr.size
local NLA_HDRLEN   = nlattr.size

local U32 = "=I4"

local ALIGNMASK = nl.ALIGNTO - 1

local function align(len)
	return (len + ALIGNMASK) & ~ALIGNMASK
end

---
-- Builds a complete netlink message.
-- @tparam integer mtype message type.
-- @tparam integer flags NLM_F_* flags.
-- @tparam integer seq sequence number.
-- @tparam string payload family header and/or attributes.
-- @treturn string the serialized message.
function message.encode(mtype, flags, seq, payload)
	return nlmsghdr:pack(NLMSG_HDRLEN + #payload, mtype, flags, seq, 0) .. payload
end

-- Iterates the length-prefixed, NLMSG-aligned records in `buf` from `pos`,
-- yielding each record's payload (the bytes past the `codec` header), its
-- type (both netlink headers put it after the length) and, for messages, the
-- flags. Stops on a truncated or malformed (short-length) record.
local function records(codec, buf, pos)
	local hdrlen = codec.size
	local size = #buf
	local last = size - hdrlen + 1
	return function()
		if pos > last then return end
		local len, rtype, flags = codec:unpack(buf, pos)
		if len < hdrlen or pos + len - 1 > size then return end
		local body = buf:sub(pos + hdrlen, pos + len - 1)
		pos = pos + align(len)
		return body, rtype, flags
	end
end

---
-- Parses a buffer into a list of `{type, flags, body}` messages, where `body`
-- holds the bytes after the `nlmsghdr` (family header and attributes).
-- @tparam string buf received buffer.
-- @treturn table list of messages.
function message.parse(buf)
	local messages = {}
	for body, mtype, flags in records(nlmsghdr, buf, 1) do
		insert(messages, {type = mtype, flags = flags, body = body})
	end
	return messages
end

local function encode_attrs(attrs)
	local out = {}
	for atype, value in pairs(attrs) do
		if type(value) == "number" then
			value = pack(U32, value)
		end
		local len = NLA_HDRLEN + #value
		insert(out, nlattr:pack(len, atype) .. value .. rep("\0", align(len) - len))
	end
	return concat(out)
end

local function parse_attrs(body, pos)
	local attrs = {}
	for value, atype in records(nlattr, body, pos) do
		attrs[atype] = value
	end
	return attrs
end

---
-- Attribute codec: serializes a `{[type] = value}` table into netlink
-- attributes, or parses them back from a message body starting at `pos`.
-- A `number` value is packed as a `u32`; a `string` is used verbatim.
-- @tparam table|string attrs attribute table (serialize) or message body (parse).
-- @tparam[opt] integer pos 1-based position of the first attribute (parse).
-- @treturn string|table the serialized attributes, or the parsed table.
function message.attrs(attrs, pos)
	return type(attrs) == "string" and parse_attrs(attrs, pos) or encode_attrs(attrs)
end

return message

