--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/loadfile test (see run.sh).
--

local test = require("util").test

local DIRECTORY <const> = "/lib/modules/lua/tests/lua/"
local SCRIPT <const> = DIRECTORY .. "loadfile.lua"

local unopened <const> = {
	[DIRECTORY .. "missing.lua"] = "ENOENT",
	[SCRIPT .. "/chunk.lua"] = "ENOTDIR",
}

for path, errno in pairs(unopened) do
	local message = "cannot open " .. path .. ": " .. errno
	test("loadfile of a path it cannot open returns " .. errno, function()
		local chunk, err = loadfile(path)
		assert(chunk == nil and err == message, "loadfile: " .. tostring(err))
	end)
	test("dofile of a path it cannot open raises " .. errno, function()
		local ok, err = pcall(dofile, path)
		assert(not ok and err == message, "dofile: " .. tostring(err))
	end)
end

