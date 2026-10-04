--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe raise test (see raise.sh).

local probe  = require("probe")
local systab = require("syscall.table")

local PREFIX <const> = "probe raise test: "
local RAISED <const> = "raised"
local CLOSED <const> = "closed object"

local kept
local raised = false
local posted = false
local looked = false
local armed  = false

local function report(what)
	print(PREFIX .. what)
end

local function raise(what)
	error(PREFIX .. what, 0) -- a position in the message would fail check_dmesg
end

local function pre()
	if not raised then
		raised = true
		raise(RAISED)
	end
end

-- the second hit's post runs last, so the regs it keeps can only have been cleared on the path that raised
local function post(_, regs)
	if posted then
		kept = regs
		raise(RAISED)
	end
	posted = true
end

local function stale()
	if kept == nil then
		return
	end
	local ok, err = pcall(kept.argument, kept, -1) -- the object is checked before the index: -1 reads no register
	report(not ok and err:find(CLOSED, 1, true) and "dropped" or "kept")
end

local function answered()
	report("answered")
end

local answers = {pre = answered}

local function lookup(_, key)
	if armed and key == "pre" and not looked then
		looked = true
		raise("lookup")
	end
	return answers[key]
end

local target = systab["personality"]
local handlers = {pre = pre, post = post}
probe.new(target, handlers)
probe.new(target, setmetatable({}, {__index = lookup}))
armed = true -- probe.new looks pre up too, to refuse one that is not a function
handlers.sentinel = setmetatable({}, {__gc = stale}) -- marked after the regs, so the close finalizes it first

