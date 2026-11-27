--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Script the darken shade test encrypts with tools/shade.sh (see run.sh).

local darken = require("darken")
local level = 2
while true do
	local info = debug.getinfo(level, "f")
	if info == nil then
		return "shaded"
	elseif info.func == darken.load or info.func == darken.run then
		return "nested"
	end
	level = level + 1
end

