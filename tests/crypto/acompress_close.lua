--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the crypto acompress close test (see acompress_close.sh).

local acompress = require("crypto").acompress
local lib = require("tests.lib")

local OWNER <const> = "not allowed from the runtime itself"

local tfm = lib.alloc(acompress, "lz4")
local req = tfm:request()
local refusal

req:compress(string.rep("a", 64), 4096, function()
	local ok, err = pcall(req.close, req)
	refusal = ok and "close accepted" or tostring(err)
end)
if refusal == nil then
	error("the driver serving lz4 completes asynchronously", 0)
end
assert(refusal:find(OWNER, 1, true), "close from the callback: " .. refusal)
req:close()
tfm:close()

