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
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/ftrace.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

typedef struct luaftrace_s {
	struct ftrace_ops fops;
	lunatik_object_t *runtime;
} luaftrace_t;

static int luaftrace_handler(lua_State *L, luaftrace_t *ftrace, unsigned long ip, unsigned long parent_ip)
{
	if (lunatik_getregistry(L, ftrace) != LUA_TFUNCTION) {
		pr_err("could not find ftrace callback\n");
		goto err;
	}

	lua_pushinteger(L, (lua_Integer)ip);
	lua_pushinteger(L, (lua_Integer)parent_ip);
	if (lua_pcall(L, 0, 2, 0) != LUA_OK) { /* callback(ip, parent_ip) */
		pr_err("%s\n", lua_tostring(L, -1));
		goto err;
	}
err:
	return 0;
}

static void notrace luaftrace_func(unsigned long ip, unsigned long parent_ip, struct ftrace_ops *fops, struct ftrace_regs *fregs)
{
	luaftrace_t *ftrace = container_of(fops, luaftrace_t, fops);
	int ret;
	lunatik_run(ftrace->runtime, luaftrace_handler, ret, ftrace, ip, parent_ip);
}

static void luaftrace_release(void *private)
{
	luaftrace_t *ftrace = (luaftrace_t *)private;

	unregister_ftrace_function(&ftrace->fops);
	lunatik_putobject(ftrace->runtime);
}

static int luaftrace_new(lua_State *L);

static const luaL_Reg luaftrace_lib[] = {
	{"new", luaftrace_new},
	{NULL, NULL}
};

static const luaL_Reg luaftrace_mt[] = {
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};

static const lunatik_class_t luaftrace_class = {
	.name = "ftrace",
	.methods = luaftrace_mt,
	.release = luaftrace_release,
	.sleep = false,
};

static int luaftrace_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luaftrace_class, sizeof(luaftrace_t));
	luaftrace_t *ftrace = (luaftrace_t *)object->private;
	struct ftrace_ops *fops = &ftrace->fops;
	int ret;

	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	memset(ftrace, 0, sizeof(luaftrace_t));

	fops->func = luaftrace_func;
	/* TODO pass flags as an argument */
	fops->flags = FTRACE_OPS_FL_SAVE_REGS | FTRACE_OPS_FL_RECURSION;

	ftrace->runtime = lunatik_toruntime(L);
	lunatik_getobject(ftrace->runtime);

	if ((ret = register_ftrace_function(fops)) != 0)
		luaL_error(L, "failed to register ftrace function (%d)", ret);

	lunatik_registerobject(L, 1, object);
	return 1; /* object */
}

LUNATIK_NEWLIB(ftrace, luaftrace_lib, &luaftrace_class, NULL);

static int __init luaftrace_init(void)
{
	return 0;
}

static void __exit luaftrace_exit(void)
{
}

module_init(luaftrace_init);
module_exit(luaftrace_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

