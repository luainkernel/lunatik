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

static int luanotifier_vt_handler (lua_State* L, void* data)
{
	struct vt_notifier_param* param = data;

	lua_pushinteger(L, param->c);
	lua_pushinteger(L, param->vc->vc_num);
	return 2;
}

static int luanotifier_handler(lua_State *L, luanotifier_t *notifier, unsigned long event, void *data)
{
	int nargs = 1; /* event */
	int ret = NOTIFY_OK;

	notifier->running = true;
	if (lunatik_getregistry(L, notifier) != LUA_TFUNCTION) {
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
	notifier->running = false;
	return ret;
}

static int luanotifier_call(struct notifier_block *nb, unsigned long event, void *data)
{
	luanotifier_t *notifier = container_of(nb, luanotifier_t, nb);
	bool islocked = !notifier->unregister; /* was called from register_fn? */
	int ret;

	if (islocked)
		lunatik_handle(notifier->runtime, luanotifier_handler, ret, notifier, event, data);
	else
		lunatik_run(notifier->runtime, luanotifier_handler, ret, notifier, event, data);

	return ret;
}

static int luanotifier_new(lua_State *, luanotifier_register_t, luanotifier_register_t, luanotifier_handler_t);

/***
* Registers a notifier for keyboard events.
* The provided callback function will be invoked whenever a console keyboard
* event occurs (e.g., a key is pressed or released).
* @function keyboard
* @tparam function callback Lua function called on keyboard events.
*   It receives the following arguments:
*
*   1. `event` (integer): The keyboard event type (see `linux.kbd`).
*   2. `down` (boolean): `true` if the key is pressed, `false` if released.
*   3. `shift` (boolean): `true` if a shift key (Shift, Alt, Ctrl) is held, `false` otherwise.
*   4. `value` (integer): The key's value (keycode or keysym, depending on the `event`).
*
*   The callback should return an integer status code from `linux.notify` (e.g. `OK`).
* @treturn notifier A new notifier object.
* @within notifier
*/
#define LUANOTIFIER_NEWCHAIN(name) 						\
static int luanotifier_##name(lua_State *L)					\
{										\
	return luanotifier_new(L, register_##name##_notifier, 			\
		unregister_##name##_notifier, luanotifier_##name##_handler);	\
}

/***
* Registers a notifier for network device events.
* The provided callback function will be invoked whenever a network device
* event occurs (e.g., an interface goes up or down).
* @function netdevice
* @tparam function callback Lua function called on netdevice events.
*   It receives the following arguments:
*
*   1. `event` (integer): The netdevice event type (see `linux.netdev`).
*   2. `name` (string): The name of the network device (e.g., "eth0").
*
*   The callback should return an integer status code from `linux.notify`.
* @treturn notifier A new notifier object.
* @within notifier
*/
LUANOTIFIER_NEWCHAIN(keyboard);
LUANOTIFIER_NEWCHAIN(netdevice);
/***
* Registers a notifier for virtual terminal (vterm) events.
* The provided callback function will be invoked whenever a virtual terminal
* event occurs (e.g., a character is written, a terminal is allocated).
* @function vterm
* @tparam function callback Lua function called on vterm events.
*   It receives the following arguments:
*
*   1. `event` (integer): The vterm event type (see `linux.vt`).
*   2. `c` (integer): The character related to the event (if applicable).
*   3. `vc_num` (integer): The virtual console number associated with the event.
*
*   The callback should return an integer status code from `linux.notify`.
* @treturn notifier A new notifier object.
* @within notifier
*/
LUANOTIFIER_NEWCHAIN(vt);

static void luanotifier_release(void *private)
{
	luanotifier_t *notifier = (luanotifier_t *)private;

	/* notifier might have never been stopped */
	if (notifier->unregister)
		notifier->unregister(&notifier->nb);

	lunatik_putobject(notifier->runtime);
}

#define luanotifier_isruntime(L, notifier)	(lunatik_toruntime(L) == (notifier)->runtime)

static inline void luanotifier_checkrunning(lua_State *L, luanotifier_t *notifier)
{
	if (luanotifier_isruntime(L, notifier) && notifier->running)
		luaL_error(L, "[%p] notifier cannot unregister itself (deadlock)", notifier);
}

/***
* Stops and unregisters a notifier.
* This method is called on a notifier object. Once stopped, the callback
* will no longer be invoked for kernel events.
* @function stop
* @treturn nil
* @raise Error if the notifier attempts to unregister itself from within its own callback (which would cause a deadlock).
* @usage my_notifier:stop()
*/
static int luanotifier_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);
	luanotifier_t *notifier = (luanotifier_t *)object->private;

	luanotifier_checkrunning(L, notifier);

	lunatik_lock(object);
	if (notifier->unregister) {
		notifier->unregister(&notifier->nb);
		notifier->unregister = NULL;
	}
	lunatik_unlock(object);

	if (luanotifier_isruntime(L, notifier))
		lunatik_unregisterobject(L, object);
	return 0;
}

static int luanotifier_delete(lua_State *L)
{
	lunatik_object_t **pobject = lunatik_checkpobject(L, 1);
	lunatik_object_t *object = *pobject;

	luanotifier_checkrunning(L, (luanotifier_t *)object->private);

	lunatik_putobject(object);
	*pobject = NULL;
	return 0;
}

static const luaL_Reg luanotifier_lib[] = {
	{"keyboard", luanotifier_keyboard},
	{"netdevice", luanotifier_netdevice},
	{"vterm", luanotifier_vt},
	{NULL, NULL}
};

static const luaL_Reg luanotifier_mt[] = {
	{"__gc", luanotifier_delete},
	{"stop", luanotifier_stop},
	{NULL, NULL}
};

static const lunatik_class_t luanotifier_class = {
	.name = "notifier",
	.methods = luanotifier_mt,
	.release = luanotifier_release,
	.opt = LUNATIK_OPT_SINGLE,
};

static int luanotifier_new(lua_State *L, luanotifier_register_t register_fn, luanotifier_register_t unregister_fn,
	luanotifier_handler_t handler_fn)
{
	lunatik_object_t *object;
	luanotifier_t *notifier;

	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	object = lunatik_newobject(L, &luanotifier_class, sizeof(luanotifier_t), LUNATIK_OPT_NONE);
	notifier = (luanotifier_t *)object->private;

	lunatik_setruntime(L, notifier, notifier);
	lunatik_getobject(notifier->runtime);

	notifier->nb.notifier_call = luanotifier_call;
	notifier->unregister = NULL;
	notifier->running = false;
	notifier->handler = handler_fn;

	lunatik_registerobject(L, 1, object);

	if (register_fn(&notifier->nb) != 0) {
		lunatik_unregisterobject(L, object);
		luaL_error(L, "couldn't create notifier");
	}

	notifier->unregister = unregister_fn;
	return 1; /* object */
}

LUNATIK_CLASSES(notifier, &luanotifier_class);
LUNATIK_NEWLIB(notifier, luanotifier_lib, luanotifier_classes, NULL);

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

