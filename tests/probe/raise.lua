--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the probe raise test (see raise.sh).

local probe  = require("probe")
local systab = require("syscall.table")

local getupvalue = debug.getupvalue

local PREFIX <const> = "probe raise test: "
local RAISED <const> = "raised"

local kept
local posted = false
local looked = false

local function report(what)
	print(PREFIX .. what)
end

local function raise(what)
	error(PREFIX .. what, 0) -- a position in the message would fail check_dmesg
end

local function pre(_, dump)
	if kept == nil then
		kept = dump
		raise(RAISED)
	end
	local _, regs = getupvalue(kept, 1)
	report(regs == nil and "dropped" or "kept")
end

local function post()
	if not posted then
		posted = true
		raise(RAISED)
	end
end

local function answered()
	report("answered")
end

local answers = {pre = answered}

local function lookup(_, key)
	if key == "pre" and not looked then
		looked = true
		raise("lookup")
	end
	return answers[key]
end

local target = systab["personality"]
probe.new(target, {pre = pre, post = post})
probe.new(target, setmetatable({}, {__index = lookup}))

