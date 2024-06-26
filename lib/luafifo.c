/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kfifo.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

LUNATIK_PRIVATECHECKER(luafifo_check, struct kfifo *);

static int luafifo_push(lua_State *L)
{
	struct kfifo *fifo = luafifo_check(L, 1);
	size_t size;
	const char *buf = luaL_checklstring(L, 2, &size);

	lua_pushinteger(L, (lua_Integer)kfifo_in(fifo, buf, size));
	return 1;
}

static int luafifo_pop(lua_State *L)
{
	struct kfifo *fifo = luafifo_check(L, 1);
	size_t size = luaL_checkinteger(L, 2);
	luaL_Buffer B;
	char *lbuf = luaL_buffinitsize(L, &B, size);

	size = kfifo_out(fifo, lbuf, size);
	luaL_pushresultsize(&B, size);
	lua_pushinteger(L, (lua_Integer)size);
	return 2;
}

static void luafifo_release(void *private)
{
	struct kfifo *fifo = (struct kfifo *)private;
	kfifo_free(fifo);
}

static int luafifo_new(lua_State *L);

static const luaL_Reg luafifo_lib[] = {
	{"new", luafifo_new},
	{NULL, NULL}
};

static const luaL_Reg luafifo_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"close", lunatik_closeobject},
	{"push", luafifo_push},
	{"pop", luafifo_pop},
	{NULL, NULL}
};

static const lunatik_class_t luafifo_class = {
	.name = "fifo",
	.methods = luafifo_mt,
	.release = luafifo_release,
	.sleep = false,
};

static int luafifo_new(lua_State *L)
{
	size_t size = luaL_checkinteger(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luafifo_class, sizeof(struct kfifo));
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	int ret;

	if ((ret = kfifo_alloc((struct kfifo *)object->private, size, gfp)) != 0)
		luaL_error(L, "failed to allocate kfifo (%d)", ret);
	return 1; /* object */
}

LUNATIK_NEWLIB(fifo, luafifo_lib, &luafifo_class, NULL);

static int __init luafifo_init(void)
{
	return 0;
}

static void __exit luafifo_exit(void)
{
}

module_init(luafifo_init);
module_exit(luafifo_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

