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

static const luaL_Reg luaset_lib[] = {
	{"new", luaset_new},
	{"labeled", luaset_labeled},
	{NULL, NULL}
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

