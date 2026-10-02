--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe argument test (see argument.sh).

local probe = require("probe")
local data  = require("data")
local rcu   = require("rcu")

local COUNT <const> = 8191 -- the size argument.sh reads
local CLOSED <const> = "closed object"
local FOREIGN <const> = "probe.regs expected"
local SINGLE <const> = "cannot share SINGLE object"

local foreign = data.new(1)
local exported = rcu.table()
local kept
local handlers = {}

local function pass(what)
	print("probe argument: " .. what)
end

local function raises(expected, method, object, ...)
	local ok, err = pcall(method, object, ...)
	return not ok and err:find(expected, 1, true) ~= nil
end

local function refused(regs)
	local methods = getmetatable(regs)
	return raises(FOREIGN, methods.dump, foreign) and raises(FOREIGN, methods.argument, foreign, 2)
end

local function export(regs)
	exported.regs = regs
end

local function pre(_, regs)
	if kept ~= nil then
		handlers.pre = nil -- the hits left find no handler, and must not leave the object pointing at them
		if rawequal(kept, regs) then
			pass("shared")
		end
		return
	end

	if regs:argument(2) ~= COUNT then
		return
	end

	pass("read")
	if not pcall(regs.argument, regs, -1) then
		pass("bounds")
	end
	if refused(regs) then
		pass("foreign")
	end
	if raises(SINGLE, export, regs) then
		pass("single")
	end
	regs:dump()
	kept = regs
end

local function stale()
	if kept == nil then
		return
	end
	local closed = raises(CLOSED, kept.argument, kept, -1) -- the object is checked first, so -1 reads no register
	if closed and raises(CLOSED, kept.dump, kept) then
		pass("stale")
	end
end

handlers.pre = pre
probe.new("vfs_read", handlers)
handlers.sentinel = setmetatable({}, {__gc = stale}) -- marked after the regs, so the close finalizes it first

