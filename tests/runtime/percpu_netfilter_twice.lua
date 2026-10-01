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
local zero = nfcount.localin(accept, 0)
local marked = nfcount.localin(accept, MARK)

netfilter.register(hook)
netfilter.register(zero) -- a second hook in the same set, told apart by a mark of 0 from one without a mark
netfilter.register(marked) -- a third, this one told apart by its mark

print("percpu netfilter twice: three targets armed")

local ok, err = pcall(netfilter.register, hook)
assert(not ok and err:find("hook already registered", 1, true), "a hook without a mark was registered twice")
netfilter.register(marked)

