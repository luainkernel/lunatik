--
-- SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
-- SPDX-License-Identifier: MIT OR GPL-2.0-only
--
-- The IPv4 LOCAL_OUT hook the netfilter mark and stop scripts register (see mark.sh and stop.sh).

local nf = require("linux.nf")

local hooks = {}

function hooks.localout(hook, mark)
	return {
		hook     = hook,
		pf       = nf.proto.IPV4,
		hooknum  = nf.inet.LOCAL_OUT,
		priority = nf.ip.pri.FILTER,
		mark     = mark,
	}
end

return hooks

