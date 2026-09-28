--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the lua/require test (see run.sh).
--

local util = require("util")

local MISSING <const> = "lunatik_no_such_module"
local REFUSAL <const> = "not allowed after module load"
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

return function()
	assert(require("util") == util, "a module the body loaded is not returned")
	refused(REFUSAL, require, MISSING)
	refused(REFUSAL, package.searchpath, MISSING, package.path)
	refused(IO_REFUSAL, require, IO)
end

