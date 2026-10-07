--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the darken shade test (see run.sh).

local test = require("tests.lib").test

local ANSWER <const> = "shaded"
local NESTED <const> = "nested"

-- the key run.sh made with shade.sh, in place of /lib/modules/lua/light.lua
package.loaded.light = require("tests.darken.shade_light")

test("a script tools/shade.sh encrypted runs with no darken call on the stack", function()
	local answer = require("tests.darken.shade_dark")
	assert(answer == ANSWER, "the dark script returned " .. tostring(answer))
end)

test("lighten.run runs the same script below darken.run", function()
	local answer = require("tests.darken.shade_run")
	assert(answer == NESTED, "the script lighten.run ran returned " .. tostring(answer))
end)

