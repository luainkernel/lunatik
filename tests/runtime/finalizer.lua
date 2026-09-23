--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the finalizer test (see finalizer.sh).

local data = require("data")

local PREFIX <const> = "finalizer test: "
local SIZE   <const> = 8
local FILL   <const> = 1 << 16

local function report(what)
	print(PREFIX .. what)
end

-- an error raised from Lua carries its position, which check_dmesg reads as a Lua error
local function verdict(ok, err)
	return ok and "accepted" or (tostring(err):gsub("^.-:%d+: ", ""):gsub("%s+$", ""))
end

local function asmethod(object)
	object:__gc()
end

local function throughmetatable(object)
	getmetatable(object).__gc(object)
end

local object = data.new(SIZE)

report("method " .. verdict(pcall(asmethod, object)))
report("metatable " .. verdict(pcall(throughmetatable, object)))
report("pcall " .. verdict(pcall(object.__gc, object)))

local function finalizer()
	report("sentinel " .. verdict(pcall(asmethod, object)))
end

local sentinel = setmetatable({}, {__gc = finalizer})
sentinel = nil
collectgarbage() -- runs the sentinel's finalizer, where the collector has stopped itself

local function hook() end

local dropped = data.new(SIZE)
dropped = nil
local stepmul = collectgarbage("param", "stepmul", 0) -- a whole cycle per step
debug.sethook(hook, "l")
local filler = {}
for i = 1, FILL do filler[i] = i end -- the hook's is the only GC checkpoint in this loop
debug.sethook()
collectgarbage("param", "stepmul", stepmul)
report("hooked")

object = nil
collectgarbage() -- the collector's own call on the object
report("collected")

local kept = data.new(SIZE) -- the close collects this one

