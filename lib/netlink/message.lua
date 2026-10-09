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
local pack, unpack, rep = string.pack, string.unpack, string.rep

local message = {}

local nlmsghdr     = struct(nl.layout.nlmsghdr)
local nlattr       = struct(nl.layout.nlattr)
local NLMSG_HDRLEN = nlmsghdr.size
local NLA_HDRLEN   = nlattr.size

local U32 = "=I4"

local ALIGNMASK = nl.align.ALIGNTO - 1

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

---
-- Serializes a `{[type] = value}` table into netlink attributes.
-- A `number` value is packed as a `u32`; a `string` is used verbatim.
-- @tparam table attrs attribute table.
-- @treturn string the serialized attributes.
function message.attrs(attrs)
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

---
-- Parses the netlink attributes of a message body into a `{[type] = value}` table.
-- A key is the raw attribute type, flag bits included: a nested attribute whose sender set
-- `NLA_F_NESTED` appears under `type | 0x8000`. A nested payload stays a string, which
-- `message.parseattrs(value)` parses in turn.
-- @tparam string body message body.
-- @tparam[opt=1] integer pos 1-based position of the first attribute.
-- @treturn table the parsed attributes.
function message.parseattrs(body, pos)
	local attrs = {}
	for value, atype in records(nlattr, body, pos or 1) do
		attrs[atype] = value
	end
	return attrs
end

---
-- Decodes a `u32` attribute value.
-- @tparam[opt] string value raw attribute payload; `nil` is passed through.
-- @treturn integer|nil the decoded integer.
function message.u32(value)
	return value and unpack(U32, value)
end

---
-- Decodes a NUL-terminated string attribute value.
-- @tparam[opt] string value raw attribute payload; `nil` is passed through.
-- @treturn string|nil the decoded string.
function message.str(value)
	return value and unpack("z", value)
end

return message

