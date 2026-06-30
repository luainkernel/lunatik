--
-- SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--

---
-- Minimal class helper for the OOP-style modules (e.g. `socket.inet`,
-- `socket.unix`). Calling the module on a table makes it an instantiable class:
-- it gains a `:new` constructor that wires `__index`/`__close` and sets the
-- class as the metatable of new objects, serving both to build instances and to
-- derive specializations (subclasses that inherit the methods).
-- @module class
-- @usage
-- local class = require("class")
--
-- local Point = class{}
-- function Point:sum() return self.x + self.y end
--
-- local point <close> = Point:new{x = 1, y = 2}   -- point:sum() == 3

local function new(self, o)
	o = o or {}
	self.__index = self
	self.__close = self.close
	return setmetatable(o, self)
end

---
-- Makes `class` an instantiable class by attaching the shared `:new`.
-- @tparam[opt] table class the class table (defaults to a fresh table).
-- @treturn table the same table, ready to receive methods and be instantiated.
return function(class)
	class = class or {}
	class.new = new
	return class
end

