--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The marked LOCAL_IN hook the percpu netfilter scripts register, and the count it keeps (see percpu_netfilter.sh).

local lunatik = require("lunatik")
local nf      = require("linux.nf")

local nfcount = {
	MARK   = 208,
	PREFIX = "nf_percpu:",
}

local env = lunatik._ENV
local key = nfcount.PREFIX .. tostring(lunatik.cpu() or "plain")

function nfcount.count()
	env[key] = (env[key] or 0) + 1
	return nf.action.ACCEPT
end

function nfcount.localin(hook, mark)
	return {
		hook     = hook,
		pf       = nf.proto.INET,
		hooknum  = nf.inet.LOCAL_IN,
		priority = nf.ip.pri.FILTER,
		mark     = mark,
	}
end

return nfcount

