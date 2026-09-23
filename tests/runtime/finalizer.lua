--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the finalizer test (see finalizer.sh).

local data = require("data")

local PREFIX <const> = "finalizer test: "
local SIZE   <const> = 8

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""):gsub("%s+$", ""))
end

local object = data.new(SIZE)

report("method " .. verdict(pcall(object.__gc, object)))
report("metatable " .. verdict(pcall(getmetatable(object).__gc, object)))

object = nil
collectgarbage()
report("collected")

