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

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/string.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef struct luaprobe_s {
	struct kprobe kp;
	lunatik_object_t *runtime;
} luaprobe_t;

static int luaprobe_handler(lua_State *L, luaprobe_t *probe, const char *handler, struct pt_regs *regs)
{
	const char *symbol_name = probe->kp.symbol_name;
	int ret = -ENXIO;

	if (lunatik_getregistry(L, probe) != LUA_TTABLE) {
		pr_err("couldn't find probe table for '%s'\n", symbol_name);
		goto err;
	}

	if (lua_getfield(L, -1, handler) != LUA_TFUNCTION) {
		pr_err("%s handler isn't defined for '%s'", handler, symbol_name);
		goto err;
	}

	lua_pushstring(L, symbol_name);
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) { /* callback(symbol_name) */
		pr_err("%s\n", lua_tostring(L, -1));
		ret = -ECANCELED;
		goto err;
	}
	ret = 0;
err:
	return ret;
}

static int __kprobes luaprobe_pre_handler(struct kprobe *kp, struct pt_regs *regs)
{
	luaprobe_t *probe = container_of(kp, luaprobe_t, kp);
	int ret;

	lunatik_run(probe->runtime, luaprobe_handler, ret, probe, "pre", regs);
	/* TODO: use the return value from the Lua callback */
	return ret;
}

static void __kprobes luaprobe_post_handler(struct kprobe *kp, struct pt_regs *regs, unsigned long flags)
{
	luaprobe_t *probe = container_of(kp, luaprobe_t, kp);
	int ret;

	/* TODO: pass flags to the Lua callback */
	lunatik_run(probe->runtime, luaprobe_handler, ret, probe, "post", regs);
	(void)ret;
}

static void luaprobe_delete(luaprobe_t *probe)
{
	struct kprobe *kp = &probe->kp;
	const char *symbol_name = kp->symbol_name;

	if (symbol_name != NULL) {
		/* XXX: it might crash if we probe functions used by the Lunatik driver
		 * for deleting the probe itself (e.g., ksys_read)
		 * see https://docs.kernel.org/trace/kprobes.html#kprobes-features-and-limitations*/
		unregister_kprobe(kp);
		kfree(symbol_name);
		kp->symbol_name = NULL;
	}
}

static void luaprobe_release(void *private)
{
	luaprobe_t *probe = (luaprobe_t *)private;

	/* device might have never been stopped */
	luaprobe_delete(probe);
	lunatik_putobject(probe->runtime);
}

static int luaprobe_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);
	luaprobe_t *probe = (luaprobe_t *)object->private;

	lunatik_lock(object);
	luaprobe_delete(probe);
	lunatik_unlock(object);

	if (lunatik_toruntime(L) == probe->runtime)
		lunatik_unregisterobject(L, object);
	return 0;
}

static int luaprobe_new(lua_State *L);

static const luaL_Reg luaprobe_lib[] = {
	{"new", luaprobe_new},
	{NULL, NULL}
};

static const luaL_Reg luaprobe_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"stop", luaprobe_stop},
	{NULL, NULL}
};

static const lunatik_class_t luaprobe_class = {
	.name = "probe",
	.methods = luaprobe_mt,
	.release = luaprobe_release,
	.sleep = false,
};

static int luaprobe_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luaprobe_class, sizeof(luaprobe_t));
	luaprobe_t *probe = (luaprobe_t *)object->private;
	struct kprobe *kp = &probe->kp;
	size_t symbol_len;
	const char *symbol_name = lua_tolstring(L, 1, &symbol_len);
	int ret;

	luaL_checktype(L, 2, LUA_TTABLE); /* handlers */

	memset(probe, 0, sizeof(luaprobe_t));

	/* TODO: use GFP from lunatik_alloc */
	kp->symbol_name = kstrndup(symbol_name, symbol_len, GFP_KERNEL);
	kp->pre_handler = luaprobe_pre_handler;
	kp->post_handler = luaprobe_post_handler;

	probe->runtime = lunatik_toruntime(L);
	lunatik_getobject(probe->runtime);

	if ((ret = register_kprobe(kp)) != 0)
		luaL_error(L, "failed to register probe (%d)", ret);

	lunatik_registerobject(L, 2, object);
	return 1; /* object */
}

LUNATIK_NEWLIB(probe, luaprobe_lib, &luaprobe_class, NULL);

static int __init luaprobe_init(void)
{
	return 0;
}

static void __exit luaprobe_exit(void)
{
}

module_init(luaprobe_init);
module_exit(luaprobe_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

