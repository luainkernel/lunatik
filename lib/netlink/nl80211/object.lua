--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Base class for the nl80211 object classes (`wiphy`, `interface`, ...): a
-- `netlink.genl` session bound to the `"nl80211"` family, caching its id and
-- carrying the shared dump-decode loop. Each object class provides its `GET`
-- dump command, its `NEW` reply command and a `decode` for the attributes, and
-- a class whose dump takes attributes a `filter` serializing the list options.
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
-- @tparam[opt] integer pid a task whose network namespace the object reaches, which holds the wiphys
--   and interfaces nl80211 answers for; the initial network namespace when absent.
-- @treturn object a new nl80211 object.
-- @raise `ESRCH` if no task has that pid, `EOPNOTSUPP` on a kernel whose sockets cannot hold a
--   namespace of their own, or `ENOENT` when the nl80211 family is not registered.
-- @see netlink.session
function object:__call(pid)
	local o = session.__call(self, pid)
	o.id = o:family("nl80211")
	return o
end

---
-- Dumps and decodes every record of the object type.
-- @tparam[opt] table opts list options, which the class's `filter` serializes into the dump's
--   attributes.
-- @treturn table list of decoded record tables.
function object:list(opts)
	local records = {}
	for _, msg in ipairs(self:dump(self.id, self.GET, self:filter(opts))) do
		if msg.cmd == self.NEW then
			insert(records, self:decode(msg.attrs))
		end
	end
	return records
end

function object:filter()
end

return object

