--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/require test (see run.sh).
--

local util = require("util")

local MISSING <const> = "lunatik_no_such_module"
local BINDING <const> = "device"
local REFUSAL <const> = "not allowed once the runtime is armed"
local IO <const> = "io"
local IO_REFUSAL <const> = "'io': process-context class in interrupt-context runtime"

package.path = "" -- a build without the refusal opens no file from the callback either

local function refused(message, f, ...)
	local ok, err = pcall(f, ...)
	assert(not ok and err:find(message, 1, true), "not refused: " .. tostring(err))
end

local ok, err = pcall(require, MISSING)
assert(not ok and err:find("not found", 1, true), "require in the body: " .. tostring(err))
local path, notfound = package.searchpath(MISSING, package.path)
assert(path == nil and notfound:find("no file", 1, true), "searchpath in the body: " .. tostring(notfound))
refused(IO_REFUSAL, require, IO)
local chunk, unopened = loadfile()
assert(chunk == nil and unopened:find("cannot open", 1, true), "loadfile in the body: " .. tostring(unopened))

return function()
	assert(require("util") == util, "a module the body loaded is not returned")
	refused(REFUSAL, require, BINDING)
	refused(REFUSAL, package.loadlib, MISSING, "luaopen_" .. MISSING) -- a build without the refusal finds nothing
	refused(REFUSAL, require, MISSING)
	refused(REFUSAL, package.searchpath, MISSING, package.path)
	refused(IO_REFUSAL, require, IO)
	local loaded, refusal = loadfile() -- no name: a build without the refusal opens no file either
	assert(loaded == nil and refusal:find(REFUSAL, 1, true), "loadfile not refused: " .. tostring(refusal))
	refused(REFUSAL, dofile)
end

