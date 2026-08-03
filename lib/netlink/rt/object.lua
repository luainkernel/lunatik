--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Base class for the rtnetlink object classes (`route`, `link`, `addr`,
-- `rule`): a `netlink.session` over the `NETLINK_ROUTE` protocol carrying the
-- shared dump loop and the routing-table id split. Each object class provides
-- its request `header`, its record `decode` and its `GET`/`NEW` (and `DEL`)
-- message types.
-- @module netlink.rt.object
-- @see netlink.session

local session = require("netlink.session")

local nl   = require("linux.netlink")
local rtnl = require("linux.rtnetlink")

local insert = table.insert

local object = session:new{proto = nl.proto.ROUTE}

-- __call is looked up raw on the metatable: pull the constructor down so the
-- classes deriving from object (session's grandchildren) stay callable
object.__call = session.__call

-- ids that do not fit the u8 table header field go in the TABLE attribute:
-- the header side keeps the ids that fit, the attr side carries the others
function object.tablemax(codec, field)
	return (1 << 8 * codec:fieldsize(field)) - 1
end

function object:headertable(tbl)
	return tbl <= self.TABLE_MAX and tbl or rtnl.table.UNSPEC
end

function object:attrtable(tbl)
	return tbl and tbl > self.TABLE_MAX and tbl or nil
end

---
-- Dumps and decodes every record of the object type.
-- @tparam[opt=AF_UNSPEC] integer family address family.
-- @treturn table list of decoded record tables.
function object:list(family)
	local records = {}
	for _, msg in ipairs(self:dump(self.GET, self:header(family))) do
		if msg.type == self.NEW then
			insert(records, self:decode(msg.body))
		end
	end
	return records
end

return object

