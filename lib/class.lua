--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Minimal class helper for the OOP-style modules (e.g. `socket.inet`,
-- `socket.unix`, `netlink.rt`). `class{}` returns a class table; `:extend{}`
-- derives a specialization that inherits its methods; `.new(...)` builds an
-- instance, running the class's `:init(...)` if it defines one; and `close`, if
-- present, is wired as the to-be-closed handler.
-- @module class
-- @usage
-- local class = require("class")
--
-- local Point = class{}
-- function Point:init(x, y) self.x, self.y = x, y end
-- function Point:sum() return self.x + self.y end
--
-- local p = Point.new(1, 2)   -- p:sum() == 3

local function closer(o)
	return o:close()
end

local function construct(class, ...)
	local o = setmetatable({}, class)
	if o.init then o:init(...) end
	return o
end

local function extend(parent, def)
	def = def or {}
	def.__index = def
	def.__close = closer
	def.new     = function(...) return construct(def, ...) end
	def.extend  = extend
	return setmetatable(def, {__index = parent})
end

---
-- Creates a class.
-- @tparam[opt] table class initial class table (shared fields and defaults).
-- @treturn table the class, ready to receive methods, be extended and instantiated.
return function(class)
	return extend(nil, class)
end

