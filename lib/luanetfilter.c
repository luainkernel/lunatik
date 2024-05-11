/*
* Copyright (c) 2024 ring-0 Ltda.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#include "linux/printk.h"
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/version.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <lunatik.h>
#include <linux/printk.h>
#include <linux/types.h>
#include <linux/list.h>
#include <net/net_namespace.h>
#include <linux/netfilter.h>
#include <linux/netfilter/x_tables.h>

static struct luanetfilter_xtable_s {
	struct list_head list;
	lunatik_object_t *runtime;
} luanetfilter_xtable_t ;

static LIST_HEAD(luanetfilter_xtable_list);

static void luanetfilter_release(void *private){
}

/* Handles target registration with the kernel. Pops the target table from the stack */
static int luanetfilter_target_reg(lua_State *L){
	pr_err("luanetfilter_target_reg\n");
	lua_pop(L,1); /* pop target table */
	return 0;
}

/* Handles target match with the kernel. Pops the match table from the stack */
static int luanetfilter_match_reg(lua_State *L){
	pr_err("luanetfilter_match_reg\n");
	lua_pop(L,1); /* pop match table */
	return 0;
}

static int luanetfilter_xtable(lua_State *L){
	pr_err("luanetfilter_xtable\n");

	luaL_checktype(L, 1, LUA_TTABLE); 

	lua_getfield(L,-1,"match");
	if(!lua_istable(L, -1)){
		pr_err("xtable: match table not found\n");
		lua_pop(L,1); /* pop arg table */
		return 0;
	}
	
	luanetfilter_match_reg(L);

	lua_getfield(L,-1,"target");
	if(!lua_istable(L,-1)){
		pr_err("xtable: target table not found\n");
		lua_pop(L,1); /* pop arg table */
		return 0;
	}

	luanetfilter_target_reg(L);

	lua_pop(L,1); /* pop arg table */
	return 0;
}

static const lunatik_reg_t netfilter_protocol[] = {
	{"UNSPEC", NFPROTO_UNSPEC},
	{"INET", NFPROTO_INET},
	{"IPV4", NFPROTO_IPV4},
	{"IPV6", NFPROTO_IPV6},
	{"ARP", NFPROTO_ARP},
	{"NETDEV", NFPROTO_NETDEV},
	{"BRIDGE", NFPROTO_BRIDGE},
	{NULL, 0}
};

static const lunatik_reg_t netfilter_action[] = {
	{"DROP", NF_DROP},
	{"ACCEPT", NF_ACCEPT},
	{"STOLEN", NF_STOLEN},
	{"QUEUE", NF_QUEUE},
	{"REPEAT", NF_REPEAT},
	{"STOP", NF_STOP},
	{"CONTINUE", XT_CONTINUE},
	{"RETURN", XT_RETURN},
	{NULL, 0}
};

static const lunatik_namespace_t luanetfilter_flags[] = {
	{"action", netfilter_action},
	{"proto", netfilter_protocol},
	{NULL, NULL}
};

static const luaL_Reg luanetfilter_lib[] = {
	{"xtable", luanetfilter_xtable},
	{NULL, NULL}
};

static const luaL_Reg luanetfilter_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};
static const lunatik_class_t luanetfilter_class = {
	.name = "netfilter",
	.methods = luanetfilter_mt,
	.release = luanetfilter_release,
	.sleep = false,
	.pointer = true,
};

LUNATIK_NEWLIB(netfilter, luanetfilter_lib, &luanetfilter_class, luanetfilter_flags);

static int __net_init luanetfilter_net_init(struct net *net){
	return 0;
};

static void __net_exit luanetfilter_net_exit(struct net *net){
};

static struct pernet_operations luanetfilter_net_ops = {
	.init = luanetfilter_net_init,
	.exit = luanetfilter_net_exit,
};

static int __init luanetfilter_init(void)
{
	pr_err("luanetfilter: loaded module");
	return register_pernet_subsys(&luanetfilter_net_ops);
}

static void __exit luanetfilter_exit(void)
{
	pr_err("luanetfilter: unloaded module");
	unregister_pernet_subsys(&luanetfilter_net_ops);
}

module_init(luanetfilter_init);
module_exit(luanetfilter_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

