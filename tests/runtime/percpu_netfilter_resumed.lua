--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test, registration from a resumed body (see percpu_netfilter.sh).

local lunatik   = require("lunatik")
local netfilter = require("netfilter")
local nfcount   = require("tests.runtime.nfcount")

local function register()
	local ok, err = pcall(netfilter.register, nfcount.localin(nfcount.count, nfcount.MARK))
	print("percpu netfilter resume: " .. tostring(lunatik.cpu() or "plain") .. " " .. tostring(ok and "registered" or err))
end

return register

