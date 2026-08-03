--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Base class for the nl80211 object classes (`wiphy`, `interface`, ...): a
-- `netlink.genl` session bound to the `"nl80211"` family, caching its id and
-- carrying the shared dump-decode loop. Each object class provides its `GET`
-- dump command, its `NEW` reply command and a `decode` for the attributes.
-- @module netlink.nl80211.object
-- @see netlink.genl

local session = require("netlink.session")
local genl    = require("netlink.genl")

local insert = table.insert

---
-- Base class for the nl80211 object classes.
-- @type object
local object = genl:new{}

---
-- Opens the genl socket, then resolves and caches the `"nl80211"` family id.
-- @treturn object a new nl80211 object.
function object:__call()
	local o = session.__call(self)
	o.id = o:family("nl80211")
	return o
end

---
-- Dumps and decodes every record of the object type.
-- @treturn table list of decoded record tables.
function object:list()
	local records = {}
	for _, msg in ipairs(self:dump(self.id, self.GET)) do
		if msg.cmd == self.NEW then
			insert(records, self:decode(msg.attrs))
		end
	end
	return records
end

return object

