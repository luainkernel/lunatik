--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test, registration from a resumed body (see percpu_netfilter.sh).

local lunatik   = require("lunatik")
local netfilter = require("netfilter")
local nfcount   = require("tests.runtime.nfcount")
local verdict   = require("tests.runtime.verdict")

local PREFIX <const> = "percpu netfilter resume: "

local hook = nfcount.localin(nfcount.count, nfcount.MARK)
local cpu = lunatik.cpu() or "plain"

local function register()
	verdict.report(PREFIX, cpu, pcall(netfilter.register, hook))
end

return register

