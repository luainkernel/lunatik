--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the netfilter register test (see register.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local test      = require("util").test
local format    = string.format

local notnumbers = {"x", "16", true}
local required   = {"pf", "hooknum", "priority"}

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

local function refuses(field, value)
	local ok, err = pcall(netfilter.register, spec(field, value))
	assert(not ok, format("netfilter.register accepted %s = %s", field, tostring(value)))
	local expected = format("bad field '%s' %%(number expected, got %s%%)", field, type(value))
	assert(err:match(expected), "netfilter.register raised something else: " .. err)
end

test("netfilter.register refuses a mark that is not a number", function()
	for _, mark in ipairs(notnumbers) do
		refuses("mark", mark)
	end
end)

test("netfilter.register refuses a required field that is missing or not a number", function()
	for _, field in ipairs(required) do
		refuses(field, nil)
		refuses(field, "2")
	end
end)

