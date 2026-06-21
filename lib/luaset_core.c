/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* A `set` is a compact, immutable set of strings, queried by binary search.
*
* It stores many short strings as a sorted blob of key bytes plus a uint32 offset
* array, with no per-key allocation, so it costs about `length + 4` bytes per key,
* instead of the hash node and slab rounding a Lua or `rcu` table pays per key.
* Built once, it is then read-only: lookups take no lock and allocate nothing, safe
* from softirq.
*
* `set.new` builds a plain set, tested for exact membership with `set:has`.
* `set.labeled` builds a labeled set: each member carries a 32-bit flag bitmask, and
* `set:match` walks a key by `.` returning the bitwise OR of the flags of every member
* that is a suffix of it (0 when nothing matches), as for domain categories.
*
* @module set
* @see rcu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include "luaset.h"

static const lunatik_class_t luaset_class;

/***
* A built plain `set`. Query it with `set:has` for exact membership, and `#` for size.
* @type set
*/

/***
* Returns whether a string is in the set.
* @function has
* @tparam string s the string to test.
* @treturn boolean whether `s` is in the set.
*/
static int luaset_has(lua_State *L)
{
	luaset_t *set = luaset_check(L, 1);
	size_t len;
	const char *s = luaL_checklstring(L, 2, &len);

	lua_pushboolean(L, luaset_find(set, s, (uint32_t)len) >= 0);
	return 1;
}

static void luaset_sort(lua_State *L, int ix)
{
	lua_getglobal(L, "table");
	lua_getfield(L, -1, "sort");
	lua_pushvalue(L, ix);
	lua_call(L, 1, 0);
	lua_pop(L, 1); /* the table library */
}

static size_t luaset_measure(lua_State *L, uint32_t *off, lua_Integer cap)
{
	lua_Integer i;
	size_t total = 0;

	for (i = 1; i <= cap; i++) {
		luaL_argcheck(L, lua_rawgeti(L, 1, i) == LUA_TSTRING, 1, "members must be strings");
		off[i - 1] = (uint32_t)total;
		total += lua_rawlen(L, -1);
		luaL_argcheck(L, total <= U32_MAX, 1, "table too large"); /* offsets are uint32 */
		lua_pop(L, 1);
	}
	off[cap] = (uint32_t)total;
	return total;
}

static void luaset_pack(lua_State *L, char *blob, const uint32_t *off, lua_Integer cap)
{
	lua_Integer i;

	for (i = 1; i <= cap; i++) {
		size_t len;
		const char *s;

		lua_rawgeti(L, 1, i);
		s = lua_tolstring(L, -1, &len);
		memcpy(blob + off[i - 1], s, len);
		lua_pop(L, 1);
	}
}

static void luaset_build(lua_State *L, luaset_t *set, lua_Integer cap)
{
	size_t total;
	char *blob;
	uint32_t *off = lunatik_malloc(L, sizeof(uint32_t) * (cap + 1));

	if (off == NULL)
		lunatik_enomem(L);
	set->off = off; /* own off before measure can raise, so release frees it */
	set->n = (size_t)cap;

	total = luaset_measure(L, off, cap);
	if (total == 0) /* no bytes to store; lookups never read blob */
		return;

	blob = lunatik_malloc(L, total);
	if (blob == NULL)
		lunatik_enomem(L);
	set->blob = blob;
	luaset_pack(L, blob, off, cap);
}

/***
* Builds a plain set from an array of strings.
*
* The array is sorted in place. The members must be unique; duplicates are kept,
* which keeps lookups correct but wastes space, so de-duplicate first if it
* matters. It allocates, so call it where it can sleep (a process-context
* runtime, or any runtime's load).
* @function new
* @tparam {string,...} strings the member strings, in any order.
* @treturn set the built set.
* @raise Error on a non-string member, if the keys exceed 4 GiB, or on
* allocation failure.
* @usage local blocked = set.new({ "evil.com", "ads.net" })
*/
static int luaset_new(lua_State *L)
{
	lunatik_object_t *object;
	luaset_t *set;

	luaL_checktype(L, 1, LUA_TTABLE);
	luaset_sort(L, 1);

	object = lunatik_newobject(L, &luaset_class, sizeof(luaset_t), LUNATIK_OPT_NONE);
	set = (luaset_t *)object->private;

	luaset_build(L, set, (lua_Integer)lua_rawlen(L, 1));
	return 1; /* object */
}

static const luaL_Reg luaset_lib[] = {
	{"new", luaset_new},
	{"labeled", luaset_labeled},
	{NULL, NULL}
};

static const luaL_Reg luaset_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__len", luaset_length},
	{"has", luaset_has},
	{NULL, NULL}
};

static const lunatik_class_t luaset_class = {
	.name = "set",
	.methods = luaset_mt,
	.release = luaset_release,
	.opt = LUNATIK_OPT_SOFTIRQ,
};

static const lunatik_class_t *luaset_classes[] = {
	&luaset_class,
	&luaset_labeled_class,
	NULL
};

LUNATIK_NEWLIB(set, luaset_lib, luaset_classes);

static int __init luaset_init(void)
{
	return 0;
}

static void __exit luaset_exit(void)
{
}

module_init(luaset_init);
module_exit(luaset_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

