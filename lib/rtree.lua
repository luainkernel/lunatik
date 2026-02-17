--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Reverse tree - maps hierarchical labels to Lunatik objects.
-- Each node is an xarray; children are stored by label, values under "".
-- @module rtree

local xarray = require("xarray")

---
-- @table rtree
local rtree = {}

---
-- @type RTree
local RTree = {}
RTree.__index = RTree

---
-- Creates a new reverse tree.
-- @function new
-- @tparam[opt] xarray xa shared xarray to use as root
-- @treturn RTree
function rtree.new(xa)
	return setmetatable({_root = xa or xarray.new()}, RTree)
end

---
-- Inserts a value at a path.
-- @function insert
-- @param value object to store
-- @tparam table labels path labels
function RTree:insert(value, labels)
	local node = self._root
	for _, label in ipairs(labels) do
		local child = node:load(label)
		if not child then
			child = xarray.new()
			node:store(label, child)
		end
		node = child
	end
	node:store("", value)
end

---
-- Looks up a value at a path.
-- @function lookup
-- @tparam table labels path labels
-- @return object or nil
function RTree:lookup(labels)
	local node = self._root
	for _, label in ipairs(labels) do
		node = node:load(label)
		if not node then
			return nil
		end
	end
	return node:load("")
end

return rtree

