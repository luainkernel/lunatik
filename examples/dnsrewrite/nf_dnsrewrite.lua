local nf = require("netfilter")
local common = require("examples.dnsrewrite.common")

local action = nf.action
local family = nf.family
local hooks = nf.inet_hooks
local pri = nf.ip_priority

local function nf_dnsrewrite_hook(skb)
	return common.hook(skb, action)
end

-- Register netfilter hooks to intercept DNS queries
nf.register{
	hook = nf_dnsrewrite_hook,
	pf = family.INET,
	hooknum = hooks.LOCAL_OUT,
	priority = pri.MANGLE + 1,
}

nf.register{
	hook = nf_dnsrewrite_hook,
	pf = family.INET,
	hooknum = hooks.PRE_ROUTING,
	priority = pri.MANGLE + 1,
}
