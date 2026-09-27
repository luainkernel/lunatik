--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- Kernel-side script for the percpu netfilter test, duplicate registration (see percpu_netfilter.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")
local nfcount   = require("tests.runtime.nfcount")

local MARK <const> = 209

local function accept(skb)
	return nf.action.ACCEPT
end

local hook = nfcount.localin(accept)
local marked = nfcount.localin(accept, MARK)

netfilter.register(hook)
netfilter.register(marked) -- a second hook in the same set, this one told apart by its mark

print("percpu netfilter twice: two targets armed")

netfilter.register(marked)

