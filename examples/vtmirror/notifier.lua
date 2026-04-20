--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- vtmirror: hardirq runtime that observes VT_WRITE events and mirrors
-- each character into a shared `data` buffer at (vc, y, x) position. Uses
-- the extended vterm callback that passes cursor coordinates along with
-- the character, so no cursor tracking is needed on the Lua side.

local notifier = require("notifier")
local notify   = require("linux.notify")
local vt       = require("linux.vt")

local MAXVTS   <const> = 8
local MAXCOLS  <const> = 200
local MAXROWS  <const> = 60
local PRINT_LO <const> = 32
local PRINT_HI <const> = 126

local grid    -- data object, set by attacher
local rowsize -- MAXCOLS, set by attacher (cached to avoid global)
local vtsize  -- MAXCOLS * MAXROWS, cached

local function is_write(event)
	return event == vt.WRITE
end

local function is_printable(c)
	return c >= PRINT_LO and c <= PRINT_HI
end

local function in_bounds(vc, x, y)
	return vc < MAXVTS and x < MAXCOLS and y < MAXROWS
end

local function callback(event, c, vc_num, x, y)
	if not is_write(event) or not is_printable(c) or not in_bounds(vc_num, x, y) then
		return notify.DONE
	end
	grid:setbyte(vc_num * vtsize + y * rowsize + x, c)
	return notify.OK
end

notifier.vterm(callback)

local function attacher(_grid)
	grid    = _grid
	rowsize = MAXCOLS
	vtsize  = MAXCOLS * MAXROWS
end
return attacher

