/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/sort.h>

#include "luaset.h"

static uint32_t luaset_walk(const luaset_t *set, const char *s, size_t len)
{
	uint32_t flags = 0;
	size_t i = 0;

	while (i <= len) {
		ssize_t idx = luaset_find(set, s + i, (uint32_t)(len - i));
		if (idx >= 0)
			flags |= set->flags[idx];
		const char *next = memchr(s + i, LUASET_SEP, len - i);
		if (next == NULL)
			break;
		i = (size_t)(next - s) + 1;
	}
	return flags;
}

/***
* A built labeled `set`. Query it with `set:match` for the union of a key's flags,
* and `#` for size.
* @type labelset
*/

/***
* Returns the union of the flags of `s` and its suffixes, or 0.
*
* Walks `s` by `.` (`"a.b.com"` tries `"a.b.com"`, `"b.com"`, `"com"`), ORing the
* flags of every level that is a member. This roots the hierarchy on the right, as
* for domains.
* @function match
* @tparam string s the string to look up.
* @treturn integer the union of the matching levels' flags, or 0.
*/
static int luaset_match(lua_State *L)
{
	luaset_t *set = luaset_check(L, 1);
	size_t len;
	const char *s = luaL_checklstring(L, 2, &len);

	lua_pushinteger(L, luaset_walk(set, s, len));
	return 1;
}

typedef struct luaset_member_s {
	const char *lstr;
	uint32_t len;
	uint32_t flag;
} luaset_member_t;

static int luaset_membercmp(const void *a, const void *b)
{
	const luaset_member_t *x = a, *y = b;
	return luaset_keycmp(x->lstr, x->len, y->lstr, y->len);
}

#define luaset_foreach(L, ix)	for (lua_pushnil(L); lua_next((L), (ix)) != 0; lua_pop((L), 1))

static size_t luaset_labeled_measure(lua_State *L, int ix, size_t *total)
{
	lua_Integer n = 0;

	*total = 0;
	luaset_foreach(L, ix) {
		size_t len;
		lua_Integer flag = lua_tointeger(L, -1);

		luaL_argcheck(L, lua_type(L, -2) == LUA_TSTRING, ix, "members must be strings");
		luaL_argcheck(L, lua_isinteger(L, -1) && flag >= 1 && flag <= U32_MAX, ix,
			"flags must be integers in [1, 2^32)");
		lua_tolstring(L, -2, &len);
		*total += len;
		n++;
	}
	luaL_argcheck(L, *total <= U32_MAX, ix, "table too large"); /* offsets are uint32 */
	return (size_t)n;
}

static void luaset_labeled_fill(lua_State *L, int ix, luaset_member_t *members)
{
	size_t i = 0;

	luaset_foreach(L, ix) {
		size_t len;
		members[i].lstr = lua_tolstring(L, -2, &len);
		members[i].len = (uint32_t)len;
		members[i].flag = (uint32_t)lua_tointeger(L, -1);
		i++;
	}
}

static void luaset_labeled_pack(uint32_t *off, char *blob, uint32_t *flags, const luaset_member_t *members, size_t n)
{
	size_t pos = 0;
	size_t i;

	for (i = 0; i < n; i++) {
		off[i] = (uint32_t)pos;
		if (members[i].len > 0)
			memcpy(blob + pos, members[i].lstr, members[i].len);
		flags[i] = members[i].flag;
		pos += members[i].len;
	}
}

static void luaset_labeled_build(lua_State *L, int ix, uint32_t *off, char *blob, uint32_t *flags, size_t n)
{
	luaset_member_t *members = lunatik_checkalloc(L, n * sizeof(luaset_member_t));

	luaset_labeled_fill(L, ix, members);
	sort(members, n, sizeof(luaset_member_t), luaset_membercmp, NULL);
	luaset_labeled_pack(off, blob, flags, members, n);
	lunatik_free(members);
}

/***
* Builds a labeled set from a table of members, each with a flag bitmask.
*
* It allocates, so call it where it can sleep (a process-context runtime, or any
* runtime's load).
* @function labeled
* @tparam {[string]=integer} t the member/flags pairs; flags are in `[1, 2^32)`.
* @treturn labelset the built labeled set.
* @raise Error on a non-string member, a flag outside `[1, 2^32)`, if the members
* exceed 4 GiB, or on allocation failure.
* @usage local cat = set.labeled({ ["a.b.c"] = 1, ["b.c"] = 2, ["c"] = 4 })
* local flags = cat:match("a.b.c")  --> 7, the union 1 | 2 | 4
*/
int luaset_labeled(lua_State *L)
{
	size_t total = 0;

	luaL_checktype(L, 1, LUA_TTABLE);
	size_t n = luaset_labeled_measure(L, 1, &total);

	lunatik_object_t *object = lunatik_newobject(L, &luaset_labeled_class, sizeof(luaset_t), LUNATIK_OPT_NONE);
	luaset_t *set = (luaset_t *)object->private;
	set->n = n;

	uint32_t *off = lunatik_checkalloc(L, sizeof(uint32_t) * (n + 1));
	set->off = off;
	off[n] = (uint32_t)total;
	if (n == 0) /* empty set: only the terminating offset */
		goto out;

	char *blob = NULL;
	if (total > 0) { /* all-empty members store no blob */
		blob = lunatik_checkalloc(L, total);
		set->blob = blob;
	}

	uint32_t *flags = lunatik_checkalloc(L, sizeof(uint32_t) * n);
	set->flags = flags;
	luaset_labeled_build(L, 1, off, blob, flags, n);
out:
	return 1; /* object */
}

static const luaL_Reg luaset_labeled_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__len", luaset_length},
	{"match", luaset_match},
	{NULL, NULL}
};

const lunatik_class_t luaset_labeled_class = {
	.name = "labelset",
	.methods = luaset_labeled_mt,
	.release = luaset_release,
	.opt = LUNATIK_OPT_SOFTIRQ,
};

