--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The netfilter registration the skb scripts share, at the filter priority (see run.sh).

local netfilter = require("netfilter")
local nf        = require("linux.nf")

local filter = {}

function filter.register(hook, pf, hooknum, mark)
	netfilter.register{
		hook     = hook,
		pf       = pf,
		hooknum  = hooknum,
		priority = nf.ip.pri.FILTER,
		mark     = mark,
	}
end

return filter

