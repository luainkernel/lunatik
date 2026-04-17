/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Notifier chain mechanism.
* This library allows Lua scripts to register callback functions that are
* invoked when specific kernel events occur, such as keyboard input,
* network device status changes, or virtual terminal events.
*
* @module notifier
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/keyboard.h>
#include <linux/netdevice.h>
#include <linux/vt_kern.h>
#include <linux/vt.h>

#include <lunatik.h>

typedef int (*luanotifier_register_t)(struct notifier_block *nb);
typedef int (*luanotifier_handler_t)(lua_State *L, void *data);

/***
* Represents a kernel notifier object.
* This is a userdata object returned by functions like `notifier.keyboard()`,
* `notifier.netdevice()`, or `notifier.vterm()`. It encapsulates a
* `struct notifier_block` and the associated Lua callback.
* @type notifier
*/

typedef struct luanotifier_s {
	struct notifier_block nb;
	lunatik_object_t *runtime;
	luanotifier_handler_t handler;
	luanotifier_register_t unregister;
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

static int luanotifier_vt_handler(lua_State *L, void *data)
{
	struct vt_notifier_param *param = data;

	lua_pushinteger(L, param->c);
	lua_pushinteger(L, param->vc->vc_num);
	return 2;
}

static int luanotifier_handler(lua_State *L, luanotifier_t *notifier, unsigned long event, void *data)
{
	int nargs = 1; /* event */

	if (lunatik_getregistry(L, notifier) != LUA_TFUNCTION)
		return NOTIFY_DONE; /* callback removed by stop() — silent no-op */

	lua_pushinteger(L, (lua_Integer)event);
	nargs += notifier->handler(L, data);
	if (lua_pcall(L, nargs, 1, 0) != LUA_OK) { /* callback(event, ...) */
		pr_err("%s\n", lua_tostring(L, -1));
		return NOTIFY_OK;
	}

	return lua_tointeger(L, -1);
}

static int luanotifier_call(struct notifier_block *nb, unsigned long event, void *data)
{
	luanotifier_t *notifier = container_of(nb, luanotifier_t, nb);
	bool islocked = !notifier->unregister; /* still inside register_fn? */
	int ret;

	if (islocked)
		lunatik_handle(notifier->runtime, luanotifier_handler, ret, notifier, event, data);
	else
		lunatik_run(notifier->runtime, luanotifier_handler, ret, notifier, event, data);

	return ret;
}

static void luanotifier_release(void *private)
{
	luanotifier_t *notifier = (luanotifier_t *)private;

	/* release always runs in process context (lua_close -> GC -> release),
	 * so unregister_*_notifier can safely sleep on synchronize_rcu */
	if (notifier->unregister)
		notifier->unregister(&notifier->nb);

	lunatik_putobject(notifier->runtime);
}

/***
* Stops event delivery to the Lua callback.
* After `stop()`, the underlying `notifier_block` remains registered in the
* kernel chain until the owning runtime is torn down, but firings become
* silent no-ops. This keeps `stop()` safe in any context (including hardirq)
* since it performs no sleeping operations; the real unregistration happens
* in `release`, which always runs in process context.
* @function stop
* @treturn nil
* @usage my_notifier:stop()
*/
static int luanotifier_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);
	luanotifier_t *notifier = (luanotifier_t *)object->private;

	lunatik_unregister(L, notifier); /* clear callback; handler becomes no-op */
	return 0;
}

static int luanotifier_new(lua_State *, luanotifier_register_t, luanotifier_register_t,
	luanotifier_handler_t, const lunatik_class_t *);

#define LUANOTIFIER_NEWCHAIN(name, class)					\
static int luanotifier_##name(lua_State *L)					\
{										\
	return luanotifier_new(L, register_##name##_notifier,			\
		unregister_##name##_notifier, luanotifier_##name##_handler,	\
		(class));							\
}

static const lunatik_class_t luanotifier_process_class;
static const lunatik_class_t luanotifier_hardirq_class;

/***
* Registers a keyboard-event notifier. Must be called from a `hardirq`
* runtime.
*
* @function keyboard
* @tparam function callback invoked as `callback(event, down, shift, value)`
*   — `event` is a `linux.kbd` code, `down` is a boolean (key pressed),
*   `shift` is a boolean (modifier held), and `value` is the keycode or
*   keysym depending on `event`. Returns a `linux.notify` status code.
* @treturn notifier
* @within notifier
*/
LUANOTIFIER_NEWCHAIN(keyboard,  &luanotifier_hardirq_class);

/***
* Registers a network-device notifier. Must be called from a process
* runtime (the default).
*
* @function netdevice
* @tparam function callback invoked as `callback(event, name)` — `event`
*   is a `linux.netdev` code and `name` is the device name (e.g. `"eth0"`).
*   Returns a `linux.notify` status code.
* @treturn notifier
* @within notifier
*/
LUANOTIFIER_NEWCHAIN(netdevice, &luanotifier_process_class);

/***
* Registers a virtual-terminal notifier. Must be called from a `hardirq`
* runtime.
*
* @function vterm
* @tparam function callback invoked as `callback(event, c, vc_num)` —
*   `event` is a `linux.vt` code, `c` is the character value, and
*   `vc_num` is the virtual console number. Returns a `linux.notify`
*   status code.
* @treturn notifier
* @within notifier
*/
LUANOTIFIER_NEWCHAIN(vt, &luanotifier_hardirq_class);

static const luaL_Reg luanotifier_lib[] = {
	{"keyboard", luanotifier_keyboard},
	{"netdevice", luanotifier_netdevice},
	{"vterm", luanotifier_vt},
	{NULL, NULL}
};

static const luaL_Reg luanotifier_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"stop", luanotifier_stop},
	{NULL, NULL}
};

static const lunatik_class_t luanotifier_process_class = {
	.name = "notifier",
	.methods = luanotifier_mt,
	.release = luanotifier_release,
	.opt = LUNATIK_OPT_SINGLE,
};

static const lunatik_class_t luanotifier_hardirq_class = {
	.name = "notifier",
	.methods = luanotifier_mt,
	.release = luanotifier_release,
	.opt = LUNATIK_OPT_HARDIRQ | LUNATIK_OPT_SINGLE,
};

static int luanotifier_new(lua_State *L, luanotifier_register_t register_fn, luanotifier_register_t unregister_fn,
	luanotifier_handler_t handler_fn, const lunatik_class_t *class)
{
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	lunatik_object_t *object = lunatik_newobject(L, class, sizeof(luanotifier_t), LUNATIK_OPT_NONE);
	luanotifier_t *notifier = (luanotifier_t *)object->private;

	notifier->runtime = lunatik_checkruntime(L, class->opt);
	lunatik_getobject(notifier->runtime);

	notifier->nb.notifier_call = luanotifier_call;
	notifier->unregister = NULL; /* sentinel: doubles as islocked marker during register_fn */
	notifier->handler = handler_fn;

	lunatik_registerobject(L, 1, object);

	if (register_fn(&notifier->nb) != 0) {
		lunatik_unregisterobject(L, object);
		luaL_error(L, "couldn't create notifier");
	}

	notifier->unregister = unregister_fn; /* set AFTER register_fn so islocked works */
	return 1; /* object */
}

LUNATIK_CLASSES(notifier, &luanotifier_process_class, &luanotifier_hardirq_class);
LUNATIK_NEWLIB(notifier, luanotifier_lib, luanotifier_classes);

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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

