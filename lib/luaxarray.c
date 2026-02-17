/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* XArray for Lua - stores Lunatik objects with string keys.
* @module xarray
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/xarray.h>
#include <linux/random.h>

#include <lunatik.h>

static unsigned int luaxarray_seed;

LUNATIK_PRIVATECHECKER(luaxarray_check, struct xarray *);

static inline unsigned long luaxarray_checkkey(lua_State *L, int idx)
{
	size_t keylen;
	const char *key = luaL_checklstring(L, idx, &keylen);
	return lunatik_hash(key, keylen, luaxarray_seed);
}

static inline int luaxarray_pushobject(lua_State *L, lunatik_object_t *object)
{
	if (!object)
		return 0;

	lunatik_cloneobject(L, object);
	return 1;
}

/***
* Stores an object at a key.
* @function store
* @param key string key
* @param object or nil to delete
* @return old object or none
*/
static int luaxarray_store(lua_State *L)
{
	lunatik_object_t *self = lunatik_checkobject(L, 1);
	struct xarray *xa = (struct xarray *)self->private;
	unsigned long index = luaxarray_checkkey(L, 2);
	lunatik_object_t *new = lunatik_checkoptnil(L, 3, lunatik_checkobject);

	lunatik_lock(self);
	lunatik_object_t *old = new ? xa_store(xa, index, new, GFP_ATOMIC) : xa_erase(xa, index);
	lunatik_unlock(self);

	if (xa_is_err(old))
		luaL_error(L, "xa_store failed: %d", xa_err(old));

	if (new)
		lunatik_getobject(new);

	return luaxarray_pushobject(L, old);
}

/***
* Loads an object from a key.
* @function load
* @param key string key
* @return object or none
*/
static int luaxarray_load(lua_State *L)
{
	struct xarray *xa = luaxarray_check(L, 1);
	unsigned long index = luaxarray_checkkey(L, 2);

	rcu_read_lock();
	lunatik_object_t *object = xa_load(xa, index);
	if (object)
		lunatik_getobject(object);
	rcu_read_unlock();

	return luaxarray_pushobject(L, object);
}

static void luaxarray_release(void *private)
{
	struct xarray *xa = (struct xarray *)private;
	unsigned long index;
	lunatik_object_t *object;

	xa_for_each(xa, index, object) {
		lunatik_putobject(object);
		xa_erase(xa, index);
	}
	xa_destroy(xa);
}

static int luaxarray_new(lua_State *L);

/***
* XArray type.
* @type xarray
*/

/***
* Creates a new XArray.
* @function new
* @return xarray
*/
static const luaL_Reg luaxarray_lib[] = {
	{"new", luaxarray_new},
	{NULL, NULL}
};

static const luaL_Reg luaxarray_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"store", luaxarray_store},
	{"load", luaxarray_load},
	{NULL, NULL}
};

static const lunatik_class_t luaxarray_class = {
	.name = "xarray",
	.methods = luaxarray_mt,
	.release = luaxarray_release,
	.sleep   = false,
	.shared  = false,
};

static int luaxarray_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luaxarray_class, sizeof(struct xarray));
	xa_init((struct xarray *)object->private);
	return 1;
}

LUNATIK_NEWLIB(xarray, luaxarray_lib, &luaxarray_class, NULL);

static int __init luaxarray_init(void)
{
	luaxarray_seed = get_random_u32();
	return 0;
}

static void __exit luaxarray_exit(void)
{
}

module_init(luaxarray_init);
module_exit(luaxarray_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_AUTHOR("Claude <noreply@anthropic.com>");

