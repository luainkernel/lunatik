--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Domain name lookup using a reverse tree.
-- Maps FQDNs to string values, splitting labels and reversing for tree storage.
-- @module dname

local rtree = require("rtree")
local data  = require("data")

---
-- @table dname
local dname = {}

---
-- @type Dname
local Dname = {}

local function todata(value)
	local d = data.new(#value)
	d:setstring(0, value)
	return d
end

local function split(name)
	local labels = {}
	for label in string.gmatch(name, "([^.]+)") do
		table.insert(labels, 1, label)
	end
	return labels
end

---
-- Looks up a value by FQDN.
-- @function __index
-- @tparam string name FQDN to look up
-- @treturn string value or nil
Dname.__index = function(self, name)
	local d = self._rtree:lookup(split(name))
	return d and d:getstring(0) or nil
end

---
-- Stores a value by FQDN.
-- @function __newindex
-- @tparam string name FQDN key
-- @tparam string value string value to store
Dname.__newindex = function(self, name, value)
	self._rtree:insert(todata(value), split(name))
end

---
-- Creates a new domain name lookup table.
-- @function new
-- @tparam[opt] xarray xa shared xarray to use as root (for sharing between runtimes)
-- @treturn Dname
function dname.new(xa)
	return setmetatable({_rtree = rtree.new(xa)}, Dname)
end

return dname

