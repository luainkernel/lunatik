--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify default test (see default.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local MOUNT     <const> = "/tmp/lunatik-fsnotify/mnt"
local MAX_ERRNO <const> = 4095

local answers = {}

function answers.nothing()
end

function answers.positive()
	return 1
end

function answers.text()
	return "deny"
end

function answers.huge()
	return -1000000
end

function answers.wide()
	return math.maxinteger
end

function answers.numeral()
	return "-1"
end

function answers.beyond()
	return -(MAX_ERRNO + 1)
end

local function guard(mask, event)
	local path = event:path()
	local name = path and string.match(path, "[^/]+$")
	print(string.format("fsnotify default test: %s mask %x", name or "?", mask))

	local answer = answers[name]
	if answer == nil then
		return
	end
	return answer()
end

local watch = fsnotify.watch(guard)
for name in pairs(answers) do
	watch:mark(MOUNT .. "/" .. name, fs.OPEN_PERM)
end

