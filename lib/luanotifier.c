/*
* Copyright (c) 2023 ring-0 Ltda.
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
#include <linux/keyboard.h>
#include <linux/netdevice.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef int (*luanotifier_register_t)(struct notifier_block *nb);
typedef int (*luanotifier_handler_t)(lua_State *L, void *data);

typedef struct luanotifier_s {
	struct notifier_block nb;
	lunatik_object_t *runtime;
	luanotifier_handler_t handler;
	luanotifier_register_t unregister;
	bool running;
} luanotifier_t;

static int luanotifier_keyboard_handler(lua_State *L, void *data)
{
	struct keyboard_notifier_param *param = (struct keyboard_notifier_param *)data;

	lua_pushboolean(L, param->down);
	lua_pushboolean(L, param->shift);
	lua_pushinteger(L, (lua_Integer)(param->value));
	return 3;
}

static int luanotifier_netdevice_handler(lua_State *L, void *data)
{
	struct net_device *dev = netdev_notifier_info_to_dev(data);

	lua_pushstring(L, dev->name);
	return 1;
}

static int luanotifier_handler(lua_State *L, luanotifier_t *notifier, unsigned long event, void *data)
{
	int nargs = 1; /* event */
	int ret = NOTIFY_OK;

	if (lua_rawgetp(L, LUA_REGISTRYINDEX, notifier) != LUA_TFUNCTION) {
		pr_err("could not find notifier callback\n");
		goto err;
	}

	lua_pushinteger(L, (lua_Integer)event);
	nargs += notifier->handler(L, data);
	if (lua_pcall(L, nargs, 1, 0) != LUA_OK) { /* callback(event, ...) */
		pr_err("%s\n", lua_tostring(L, -1));
		goto err;
	}

	ret = lua_tointeger(L, -1);
err:
	return ret;
}

static int luanotifier_call(struct notifier_block *nb, unsigned long event, void *data)
{
	luanotifier_t *notifier = container_of(nb, luanotifier_t, nb);
	int ret;

	if (notifier->running)
		lunatik_handle(notifier->runtime, luanotifier_handler, ret, notifier, event, data);
	else {
		notifier->running = true;
		lunatik_run(notifier->runtime, luanotifier_handler, ret, notifier, event, data);
		notifier->running = false;
	}
	return ret;
}

static int luanotifier_new(lua_State *, luanotifier_register_t, luanotifier_register_t, luanotifier_handler_t);

#define LUANOTIFIER_NEWCHAIN(name) 						\
static int luanotifier_##name(lua_State *L)					\
{										\
	return luanotifier_new(L, register_##name##_notifier, 			\
		unregister_##name##_notifier, luanotifier_##name##_handler);	\
}

LUANOTIFIER_NEWCHAIN(keyboard);
LUANOTIFIER_NEWCHAIN(netdevice);

static void luanotifier_release(void *private)
{
	luanotifier_t *notifier = (luanotifier_t *)private;
	lunatik_object_t *runtime = notifier->runtime;
	lua_State *L = lunatik_getstate(runtime);

	if (notifier->running == true)
		luaL_error(L, "cannot delete notifier while running it");

	notifier->unregister(&notifier->nb);

	lua_pushnil(L);
	lua_rawsetp(L, LUA_REGISTRYINDEX, notifier); /* pop nil */

	lunatik_putobject(runtime);
}

static const luaL_Reg luanotifier_lib[] = {
	{"keyboard", luanotifier_keyboard},
	{"netdevice", luanotifier_netdevice},
	{"delete", lunatik_closeobject},
	{NULL, NULL}
};

static const luaL_Reg luanotifier_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
	{"delete", lunatik_closeobject},
	{NULL, NULL}
};

static const lunatik_reg_t luanotifier_notify[] = {
	{"DONE", NOTIFY_DONE},
	{"OK", NOTIFY_OK},
	{"BAD", NOTIFY_BAD},
	{"STOP", NOTIFY_STOP},
	{NULL, 0}
};

static const lunatik_reg_t luanotifier_kbd[] = {
	{"KEYCODE", KBD_KEYCODE},
	{"UNBOUND_KEYCODE", KBD_UNBOUND_KEYCODE},
	{"UNICODE", KBD_UNICODE},
	{"KEYSYM", KBD_KEYSYM},
	{"POST_KEYSYM", KBD_POST_KEYSYM},
	{NULL, 0}
};

static const lunatik_reg_t luanotifier_netdev[] = {
	{"UP", NETDEV_UP},
	{"DOWN", NETDEV_DOWN},
	{"REBOOT", NETDEV_REBOOT},
	{"CHANGE", NETDEV_CHANGE},
	{"REGISTER", NETDEV_REGISTER},
	{"UNREGISTER", NETDEV_UNREGISTER},
	{"CHANGEMTU", NETDEV_CHANGEMTU},
	{"CHANGEADDR", NETDEV_CHANGEADDR},
	{"PRE_CHANGEADDR", NETDEV_PRE_CHANGEADDR},
	{"GOING_DOWN", NETDEV_GOING_DOWN},
	{"CHANGENAME", NETDEV_CHANGENAME},
	{"FEAT_CHANGE", NETDEV_FEAT_CHANGE},
	{"BONDING_FAILOVER", NETDEV_BONDING_FAILOVER},
	{"PRE_UP", NETDEV_PRE_UP},
	{"PRE_TYPE_CHANGE", NETDEV_PRE_TYPE_CHANGE},
	{"POST_TYPE_CHANGE", NETDEV_POST_TYPE_CHANGE},
	{"POST_INIT", NETDEV_POST_INIT},
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0))
	{"PRE_UNINIT", NETDEV_PRE_UNINIT},
#endif
	{"RELEASE", NETDEV_RELEASE},
	{"NOTIFY_PEERS", NETDEV_NOTIFY_PEERS},
	{"JOIN", NETDEV_JOIN},
	{"CHANGEUPPER", NETDEV_CHANGEUPPER},
	{"RESEND_IGMP", NETDEV_RESEND_IGMP},
	{"PRECHANGEMTU", NETDEV_PRECHANGEMTU},
	{"CHANGEINFODATA", NETDEV_CHANGEINFODATA},
	{"BONDING_INFO", NETDEV_BONDING_INFO},
	{"PRECHANGEUPPER", NETDEV_PRECHANGEUPPER},
	{"CHANGELOWERSTATE", NETDEV_CHANGELOWERSTATE},
	{"UDP_TUNNEL_PUSH_INFO", NETDEV_UDP_TUNNEL_PUSH_INFO},
	{"UDP_TUNNEL_DROP_INFO", NETDEV_UDP_TUNNEL_DROP_INFO},
	{"CHANGE_TX_QUEUE_LEN", NETDEV_CHANGE_TX_QUEUE_LEN},
	{"CVLAN_FILTER_PUSH_INFO", NETDEV_CVLAN_FILTER_PUSH_INFO},
	{"CVLAN_FILTER_DROP_INFO", NETDEV_CVLAN_FILTER_DROP_INFO},
	{"SVLAN_FILTER_PUSH_INFO", NETDEV_SVLAN_FILTER_PUSH_INFO},
	{"SVLAN_FILTER_DROP_INFO", NETDEV_SVLAN_FILTER_DROP_INFO},
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 18, 0))
	{"OFFLOAD_XSTATS_ENABLE", NETDEV_OFFLOAD_XSTATS_ENABLE},
	{"OFFLOAD_XSTATS_DISABLE", NETDEV_OFFLOAD_XSTATS_DISABLE},
	{"OFFLOAD_XSTATS_REPORT_USED", NETDEV_OFFLOAD_XSTATS_REPORT_USED},
	{"OFFLOAD_XSTATS_REPORT_DELTA", NETDEV_OFFLOAD_XSTATS_REPORT_DELTA},
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 3, 0))
	{"XDP_FEAT_CHANGE", NETDEV_XDP_FEAT_CHANGE},
#endif
	{NULL, 0}
};

static const lunatik_namespace_t luanotifier_flags[] = {
	{"notify", luanotifier_notify},
	{"kbd", luanotifier_kbd},
	{"netdev", luanotifier_netdev},
	{NULL, NULL}
};

static const lunatik_class_t luanotifier_class = {
	.name = "notifier",
	.methods = luanotifier_mt,
	.release = luanotifier_release,
	.sleep = true,
};

static int luanotifier_new(lua_State *L, luanotifier_register_t register_fn, luanotifier_register_t unregister_fn,
	luanotifier_handler_t handler_fn)
{
	lunatik_object_t *object;
	luanotifier_t *notifier;

	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	object = lunatik_newobject(L, &luanotifier_class, sizeof(luanotifier_t));
	notifier = (luanotifier_t *)object->private;

	notifier->runtime = lunatik_toruntime(L);
	lunatik_getobject(notifier->runtime);

	notifier->nb.notifier_call = luanotifier_call;
	notifier->unregister = unregister_fn;
	notifier->handler = handler_fn;

	lua_pushvalue(L, 1);  /* push callback */
	lua_rawsetp(L, LUA_REGISTRYINDEX, notifier); /* pop callback */

	notifier->running = true; /* notifier_call might be called directly (e.g., NETDEV_REGISTER) */
	if (register_fn(&notifier->nb) != 0)
		luaL_error(L, "couldn't create notifier");
	notifier->running = false;

	return 1; /* object */
}

LUNATIK_NEWLIB(notifier, luanotifier_lib, &luanotifier_class, luanotifier_flags);

static int __init luanotifier_init(void)
{
	return 0;
}

static void __exit luanotifier_exit(void)
{
}

module_init(luanotifier_init);
module_exit(luanotifier_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

