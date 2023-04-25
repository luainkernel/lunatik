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
#include <linux/keyboard.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

#define LUANOTIFIER_MT	"notifier"

typedef struct luanotifier_s {
	struct notifier_block nb;
	lunatik_runtime_t *runtime;
	int ud;
	bool running;
} luanotifier_t;

static int luanotifier_handler(lua_State *L, int ud, unsigned long event,
	int down, int shift, unsigned int key)
{
	int ret = NOTIFY_OK;

	if (lua_rawgeti(L, LUA_REGISTRYINDEX, ud) != LUA_TUSERDATA ||
	    lua_getiuservalue(L, -1, 1) != LUA_TFUNCTION) {
		pr_err("could not find notifier callback\n");
		goto err;
	}

	lua_pushinteger(L, (lua_Integer)event);
	lua_pushboolean(L, down);
	lua_pushboolean(L, shift);
	lua_pushinteger(L, (lua_Integer)key);
	if (lua_pcall(L, 4, 1, 0) != LUA_OK) { /* callback(event, down, shift, keycode) */
		pr_err("%s\n", lua_tostring(L, -1));
		goto err;
	}

	ret = lua_tointeger(L, -1);
err:
	return ret;
}

static int luanotifier_cb(struct notifier_block *nb, unsigned long event, void *data)
{
	struct keyboard_notifier_param *param = (struct keyboard_notifier_param *)data;
	luanotifier_t *notifier = container_of(nb, luanotifier_t, nb);
	int ret;

	notifier->running = true;
	lunatik_run(notifier->runtime, luanotifier_handler, ret, notifier->ud, event,
			param->down, param->shift, param->value);
	notifier->running = false;
	return ret;
}

static int luanotifier_keyboard(lua_State *L)
{
	luanotifier_t *notifier;

	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	notifier = (luanotifier_t *)lua_newuserdatauv(L, sizeof(luanotifier_t), 1);
	notifier->runtime = lunatik_toruntime(L);
	notifier->nb.notifier_call = luanotifier_cb;
	notifier->running = false;

	register_keyboard_notifier(&notifier->nb);

	luaL_setmetatable(L, LUANOTIFIER_MT);
	lua_pushvalue(L, 1);  /* push callback */
	lua_setiuservalue(L, -2, 1); /* pops callback */

	lua_pushvalue(L, -1);  /* push userdata */
	notifier->ud = luaL_ref(L, LUA_REGISTRYINDEX); /* pops userdata */

	return 1; /* userdata */
}

static int luanotifier_delete(lua_State *L)
{
	luanotifier_t *notifier = (luanotifier_t *)luaL_checkudata(L, 1, LUANOTIFIER_MT);
	lunatik_runtime_t *runtime = notifier->runtime;

	if (notifier->running == true)
		luaL_error(L, "cannot delete notifier while running it");

	if (runtime == NULL)
		goto out;

	unregister_keyboard_notifier(&notifier->nb);
	luaL_unref(runtime->L, LUA_REGISTRYINDEX, notifier->ud);
	notifier->ud = LUA_NOREF;
	notifier->runtime = NULL;
out:
	return 0;
}

static const luaL_Reg luanotifier_lib[] = {
	{"keyboard", luanotifier_keyboard},
	{"delete", luanotifier_delete},
	{NULL, NULL}
};

static const luaL_Reg luanotifier_mt[] = {
	{"__gc", luanotifier_delete},
	{"__close", luanotifier_delete},
	{"delete", luanotifier_delete},
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

static const lunatik_namespace_t luanotifier_flags[] = {
	{"notify", luanotifier_notify},
	{"kbd", luanotifier_kbd},
	{NULL, NULL}
};

static const lunatik_class_t luanotifier_class = {
	.name = LUANOTIFIER_MT,
	.methods = luanotifier_mt,
};

LUNATIK_NEWLIB(notifier, luanotifier_lib, &luanotifier_class, luanotifier_flags, true);

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

