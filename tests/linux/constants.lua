--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the linux.constants test (see run.sh).
--

local linux     = require("linux")
local errno     = require("linux.errno")
local nf        = require("linux.nf")
local rtnetlink = require("linux.rtnetlink")
local tc        = require("linux.tc")
local test      = require("util").test
local check     = require("tests.linux.check")

local INT_MIN <const> = -0x80000000
local INT_MAX <const> = 0x7FFFFFFF

test("an unsigned 32-bit constant past INT_MAX keeps its unsigned value", function()
	check.carries("tc.h", tc.h, { ROOT = 0xFFFFFFFF, INGRESS = 0xFFFFFFF1, MAJ_MASK = 0xFFFF0000 })
	check.carries("rtnetlink.table", rtnetlink.table, { MAX = 0xFFFFFFFF })
end)

test("a signed constant below zero keeps its sign", function()
	check.carries("tc.action", tc.action, { UNSPEC = -1 })
	check.carries("nf.ip.pri", nf.ip.pri, { FIRST = INT_MIN, RAW = -300 })
	check.carries("nf.br.pri", nf.br.pri, { FIRST = INT_MIN })
end)

test("a constant within INT_MAX keeps its value", function()
	check.carries("tc.h", tc.h, { MIN_MASK = 0xFFFF })
	check.carries("rtnetlink.table", rtnetlink.table, { MAIN = 254 })
	check.carries("nf.ip.pri", nf.ip.pri, { LAST = INT_MAX })
end)

test("linux.errno holds each errno positive, keyed by the name linux.errname gives it", function()
	check.carries("errno", errno, { EPERM = 1, ENOENT = 2, EAGAIN = 11, ENOMEM = 12, EACCES = 13, EINVAL = 22 })
	for key, value in pairs(errno) do
		local name = linux.errname(value)
		assert(value > 0 and errno[name] == value, ("linux.errno.%s: %d is %s"):format(key, value, name))
	end
end)

