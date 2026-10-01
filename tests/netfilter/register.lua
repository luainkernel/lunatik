--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netfilter register test (see register.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local test      = require("tests.lib").test
local format    = string.format

local MARK <const> = 0x10
local U8   <const> = 1 << 8  -- past the u8 pf
local U32  <const> = 1 << 32 -- past the unsigned int hooknum and the u32 mark
local S32  <const> = 1 << 31 -- past the int priority, on either side

local notnumbers = {"x", "16", true}
local required   = {"pf", "hooknum", "priority"}

-- past each field's type, with low bits that a truncating build registers as a hook of this script's own
local pastrange = {
	pf       = {nf.proto.INET - U8, nf.proto.INET | U8},
	hooknum  = {nf.inet.LOCAL_OUT - U32, nf.inet.LOCAL_OUT | U32},
	priority = {-S32 - 1, S32},
	mark     = {MARK - U32, MARK | U32},
}

local function accept()
	return nf.action.ACCEPT
end

local function spec(field, value)
	local opts = {
		hook     = accept,
		pf       = nf.proto.INET,
		hooknum  = nf.inet.LOCAL_OUT,
		priority = nf.ip.pri.FILTER,
	}
	opts[field] = value
	return opts
end

local function refuses(field, value, expected)
	local ok, err = pcall(netfilter.register, spec(field, value))
	assert(not ok, format("netfilter.register accepted %s = %s", field, tostring(value)))
	assert(err:match(expected), "netfilter.register raised something else: " .. err)
end

local function nonumber(field, value)
	refuses(field, value, format("bad field '%s' %%(number expected, got %s%%)", field, type(value)))
end

test("netfilter.register refuses a mark that is not a number", function()
	for _, mark in ipairs(notnumbers) do
		nonumber("mark", mark)
	end
end)

test("netfilter.register refuses a required field that is missing or not a number", function()
	for _, field in ipairs(required) do
		nonumber(field, nil)
		nonumber(field, "2")
	end
end)

test("netfilter.register refuses a field past its range", function()
	for field, values in pairs(pastrange) do
		local expected = format("bad field '%s' %%(out of bounds%%)", field)
		for _, value in ipairs(values) do
			refuses(field, value, expected)
		end
	end
end)

test("netfilter.register accepts a mark at the top of its range", function()
	netfilter.register(spec("mark", U32 - 1))
end)

test("netfilter.register accepts a priority at either end of an int", function()
	netfilter.register(spec("priority", nf.ip.pri.FIRST))
	netfilter.register(spec("priority", nf.ip.pri.LAST))
end)

