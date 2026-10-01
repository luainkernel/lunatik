--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/loadfile test (see run.sh).
--

local test = require("util").test

local PARENT <const> = "/lib/modules/"
local DIRECTORY <const> = "lua"
local PATH <const> = PARENT .. DIRECTORY
local ERRNO <const> = "EINVAL"

test("loadfile of a directory returns the errno's name", function()
	local chunk, err = loadfile(PATH)
	assert(chunk == nil and err == ERRNO, "loadfile: " .. tostring(err))
end)

test("dofile of a directory raises the errno's name", function()
	local ok, err = pcall(dofile, PATH)
	assert(not ok and err == ERRNO, "dofile: " .. tostring(err))
end)

test("require of a directory raises the errno's name", function()
	local path = package.path
	package.path = PARENT .. "?"
	local ok, err = pcall(require, DIRECTORY)
	package.path = path
	assert(not ok and err:find("\t" .. ERRNO, 1, true), "require: " .. tostring(err))
end)

