--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the fsnotify expired test (see expired.sh).

local fsnotify = require("fsnotify")
local fs       = require("linux.fs")

local SCRATCH <const> = "/tmp/lunatik-fsnotify"
local KEPT    <const> = SCRATCH .. "/kept"
local PROBE   <const> = SCRATCH .. "/probe"

local kept

local function keep(mask, event)
	kept = event
	print(string.format("fsnotify expired test note: kept the event for ino %s", event:ino()))
end

local function probe(mask, event)
	if kept == nil then
		print("fsnotify expired test fail: the keeper never ran")
		return
	end

	local ok, err = pcall(kept.ino, kept)
	if ok then
		print("fsnotify expired test fail: the kept event still answered")
	elseif not tostring(err):match("null pointer dereference") then
		print("fsnotify expired test fail: " .. tostring(err))
	else
		print("fsnotify expired test pass: the kept event raised")
	end
end

local keeper = fsnotify.watch(keep)
keeper:mark(KEPT, fs.OPEN)

local prober = fsnotify.watch(probe)
prober:mark(PROBE, fs.OPEN)

