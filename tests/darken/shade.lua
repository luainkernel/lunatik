--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the darken shade test (see run.sh).

local test = require("tests.lib").test

local ANSWER <const> = "shaded"

-- the key run.sh made with shade.sh, in place of /lib/modules/lua/light.lua
package.loaded.light = require("tests.darken.shade_light")

test("lighten.run runs a script tools/shade.sh encrypted", function()
	local answer = require("tests.darken.shade_dark")
	assert(answer == ANSWER, "the dark script returned " .. tostring(answer))
end)

