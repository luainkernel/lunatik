/*
* Copyright (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
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

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/version.h>
#include <linux/netfilter.h>
#include <linux/netfilter/x_tables.h>

#include <lua.h>
#include <lauxlib.h>
#include <lunatik.h>

typedef struct luanetfilter_xtable_s {
	lunatik_object_t *runtime;
} luanetfilter_xtable_t;

static int luanetfilter_xtable(lua_State *L);

static void luanetfilter_release(void *private)
{
	luanetfilter_xtable_t *luaxtable = (luanetfilter_xtable_t *)private;
	lunatik_putobject(luaxtable->runtime);
}

static const lunatik_reg_t luanetfilter_protocol[] = {
	{"UNSPEC", NFPROTO_UNSPEC},
	{"INET", NFPROTO_INET},
	{"IPV4", NFPROTO_IPV4},
	{"IPV6", NFPROTO_IPV6},
	{"ARP", NFPROTO_ARP},
	{"NETDEV", NFPROTO_NETDEV},
	{"BRIDGE", NFPROTO_BRIDGE},
	{NULL, 0}
};

static const lunatik_reg_t luanetfilter_action[] = {
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
	{"action", luanetfilter_action},
	{"proto", luanetfilter_protocol},
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
};

static int luanetfilter_xtable(lua_State *L)
{
	lunatik_object_t *object;
	luanetfilter_xtable_t *luaxtable;

	object = lunatik_newobject(L, &luanetfilter_class, sizeof(luanetfilter_xtable_t));
	luaxtable = (luanetfilter_xtable_t *)object->private;

	luaxtable->runtime = lunatik_toruntime(L);
	lunatik_getobject(luaxtable->runtime);
	return 1;
}

LUNATIK_NEWLIB(netfilter, luanetfilter_lib, &luanetfilter_class, luanetfilter_flags);

static int __init luanetfilter_init(void)
{
	return 0;
}

static void __exit luanetfilter_exit(void)
{
}

module_init(luanetfilter_init);
module_exit(luanetfilter_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>");

