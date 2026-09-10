--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Key management. An `nl80211` object over the `"nl80211"` generic netlink
-- family: create an instance with `netlink.nl80211.key()` then install and
-- remove the pairwise (PTK) and group (GTK) keys of an AP interface; the
-- underlying socket is closed by `close()` (or the to-be-closed `__close`). All
-- methods block and require a sleepable runtime.
--
-- @module netlink.nl80211.key
-- @see netlink.nl80211.object
--

local object  = require("netlink.nl80211.object")
local message = require("netlink.message")

local cmd  = require("linux.nl80211").cmd
local attr = require("linux.nl80211").attr

local pack = string.pack

---
-- @type key

---
-- Creates a new key object.
-- @function key:new
-- @tparam[opt] table o an initial object table.
-- @treturn key the new key object.
-- @see class
local key = object:new{NEW = cmd.NEW_KEY, DEL = cmd.DEL_KEY}

---
-- Installs a key on an AP interface. A `mac` makes it a pairwise (PTK) key for
-- that station; without one it is a group (GTK) key.
-- @tparam table opts key parameters: `ifindex`, `index` (0-7), `cipher` (a
--   `linux.nl80211.cipher` suite), `data` (the raw key bytes); optional `mac`
--   and `seq` (the raw receive sequence counter).
-- @raise on a netlink error.
function key:add(opts)
	self:call(self.id, self.NEW, 0, message.attrs{
		[attr.IFINDEX]    = opts.ifindex,
		[attr.KEY_IDX]    = pack("=I1", opts.index),
		[attr.KEY_CIPHER] = opts.cipher,
		[attr.KEY_DATA]   = opts.data,
		[attr.MAC]        = opts.mac,
		[attr.KEY_SEQ]    = opts.seq,
	})
end

---
-- Removes a key from an AP interface. A `mac` selects the pairwise key of that
-- station; without one it is the group key.
-- @tparam table opts key parameters: `ifindex`, `index` and optional `mac`.
-- @raise on a netlink error.
function key:del(opts)
	self:call(self.id, self.DEL, 0, message.attrs{
		[attr.IFINDEX] = opts.ifindex,
		[attr.KEY_IDX] = pack("=I1", opts.index),
		[attr.MAC]     = opts.mac,
	})
end

return key

