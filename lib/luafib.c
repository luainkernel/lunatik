/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Forwarding Information Base (FIB) rules.
* This library allows Lua scripts to add and delete FIB rules, similar to the
* user-space `ip rule add` and `ip rule del` commands.
* FIB rules are used to influence routing decisions by selecting different
* routing tables based on various criteria.
*
* @module fib
*/
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <net/fib_rules.h>

#include <lunatik.h>

#define luafib_nl_sizeof(t)	(nla_total_size(sizeof(t)))

#define LUAFIB_NL_SIZE	(NLMSG_ALIGN(sizeof(struct fib_rule_hdr)) 	\
		+ luafib_nl_sizeof(u8)		/* FRA_PROTOCOL */	\
		+ luafib_nl_sizeof(u32))	/* FRA_PRITORITY */

typedef struct luafib_rule_s {
	struct net *net;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
	int (*command)(struct net *, struct sk_buff *, struct nlmsghdr *, struct netlink_ext_ack *, bool);
#else
	int (*command)(struct sk_buff *, struct nlmsghdr *, struct netlink_ext_ack *);
#endif
	u32 table;
	u32 priority;
} luafib_rule_t;

static int luafib_nl_rule(luafib_rule_t *rule)
{
	struct fib_rule_hdr *frh;
	struct nlmsghdr *nlh;
	struct sk_buff *skb;
	int ret = -1;

	if (!(skb = nlmsg_new(LUAFIB_NL_SIZE, GFP_KERNEL)) ||
	    !(nlh = nlmsg_put(skb, 0, 0, 0, sizeof(*frh), 0)))
		goto out;

	nlh->nlmsg_flags |= NLM_F_EXCL;

	frh = nlmsg_data(nlh);
	memset(frh, 0, sizeof(*frh));
	frh->family = AF_INET;
	frh->action = FR_ACT_TO_TBL;
	frh->table = rule->table;

	if (nla_put_u8(skb, FRA_PROTOCOL, RTPROT_KERNEL) ||
	    nla_put_u32(skb, FRA_PRIORITY, rule->priority))
		goto free;
	nlmsg_end(skb, nlh);

	skb->sk = rule->net->rtnl;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
	ret = rule->command(rule->net, skb, nlh, NULL, true);
#else
	ret = rule->command(skb, nlh, NULL);
#endif
free:
	nlmsg_free(skb);
out:
	return ret;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
#define LUAFIB_RULECOMMAND(op) fib_##op
#else
#define LUAFIB_RULECOMMAND(op) fib_nl_##op
#endif

#define LUAFIB_OPRULE(op) 				\
static int luafib_##op(lua_State *L)			\
{							\
	luafib_rule_t rule;				\
							\
	rule.net = &init_net;				\
	rule.command = LUAFIB_RULECOMMAND(op);		\
	rule.table = (u32)luaL_checkinteger(L, 1);	\
	rule.priority = (u32)luaL_checkinteger(L, 2);	\
							\
	if (luafib_nl_rule(&rule) < 0)			\
		luaL_error(L, "failed on " #op);	\
							\
	return 0;					\
}

/***
* Adds a new FIB rule.
* This function binds the kernel `fib_nl_newrule` API. It creates a new FIB rule
* that directs lookups to the specified routing `table` for packets matching
* this rule's `priority`.
*
* Note: This function creates a relatively simple rule. The rule is always for
* IPv4 (`AF_INET`), the action is always to look up the specified `table`
* (`FR_ACT_TO_TBL`), and the protocol is set to `RTPROT_KERNEL`. It does not
* support specifying other match conditions (e.g., source/destination IP, interface, fwmark).
*
* @function newrule
* @tparam integer table The routing table identifier (e.g., 254 for main, 255 for local).
* @tparam integer priority The priority of the rule. Lower numbers have higher precedence.
* @treturn nil
* @raise Error if the rule cannot be added (e.g., due to kernel error, invalid parameters).
* @usage
*   fib.newrule(100, 10000) -- Add a rule with priority 10000 to lookup table 100
*/
LUAFIB_OPRULE(newrule);

/***
* Deletes an existing FIB rule.
* This function binds the kernel `fib_nl_delrule` API. It removes a FIB rule
* that matches the specified routing `table` and `priority`.
*
* @function delrule
* @tparam integer table The routing table identifier of the rule to delete.
* @tparam integer priority The priority of the rule to delete.
* @treturn nil
* @raise Error if the rule cannot be deleted (e.g., rule not found, kernel error).
* @usage
*   fib.delrule(100, 10000) -- Delete the rule with priority 10000 that looks up table 100
*/
LUAFIB_OPRULE(delrule);

static const luaL_Reg luafib_lib[] = {
	{"newrule", luafib_newrule},
	{"delrule", luafib_delrule},
	{NULL, NULL}
};

static const lunatik_class_t luafib_class = {
	.sleep = true,
};

LUNATIK_NEWLIB(fib, luafib_lib, &luafib_class, NULL);

static int __init luafib_init(void)
{
	return 0;
}

static void __exit luafib_exit(void)
{
}

module_init(luafib_init);
module_exit(luafib_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

