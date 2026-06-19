/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* A compact, immutable set of strings, each tagged with a 32-bit bitmask, queried by
* binary search over a sorted blob. Built once by `set.new`, it is then read-only:
* lookups take no lock and allocate nothing, safe from softirq.
*
* `set:has` returns the tag of an exact member; `set:suffix` and `set:prefix` return
* the bitwise OR of the tags of every matching segment, the union over the hierarchy.
* Any lookup returns 0 when nothing matches.
*
* @module set
* @see rcu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/string.h>
#include <linux/sort.h>

#include <lunatik.h>

typedef struct luaset_s {
	uint32_t n;		/* number of members */
	const uint32_t *off;	/* n+1 offsets into blob */
	const char *blob;	/* sorted members concatenated, no separator */
	const uint32_t *tags;	/* n tags, one per member */
} luaset_t;

#define luaset_tag(set, idx)	((set)->tags[idx])

static int luaset_new(lua_State *L);
static const lunatik_class_t luaset_class;

LUNATIK_PRIVATECHECKER(luaset_check, luaset_t *);

static inline int luaset_compare(const char *a, uint32_t alen, const char *b, uint32_t blen)
{
	uint32_t m = min(alen, blen);
	int c = memcmp(a, b, m);
	return c != 0 ? c : (alen > blen) - (alen < blen);
}

static int luaset_find(const luaset_t *set, const char *s, uint32_t len)
{
	int lo = 0, hi = (int)set->n - 1;

	while (lo <= hi) {
		int mid = lo + (hi - lo) / 2;
		const char *m = set->blob + set->off[mid];
		uint32_t mlen = set->off[mid + 1] - set->off[mid];
		int c = luaset_compare(s, len, m, mlen);

		if (c == 0)
			return mid;
		if (c < 0)
			hi = mid - 1;
		else
			lo = mid + 1;
	}
	return -1;
}

static uint32_t luaset_walksuffix(const luaset_t *set, const char *s, size_t len, char sep)
{
	uint32_t tags = 0;
	size_t i = 0;

	while (i <= len) {
		int idx = luaset_find(set, s + i, (uint32_t)(len - i));
		if (idx >= 0)
			tags |= luaset_tag(set, idx);
		const char *next = memchr(s + i, sep, len - i);
		if (next == NULL)
			break;
		i = (size_t)(next - s) + 1;
	}
	return tags;
}

static uint32_t luaset_walkprefix(const luaset_t *set, const char *s, size_t len, char sep)
{
	uint32_t tags = 0;

	while (len > 0) {
		int idx = luaset_find(set, s, (uint32_t)len);
		if (idx >= 0)
			tags |= luaset_tag(set, idx);
		while (len > 0 && s[len - 1] != sep)
			len--;
		if (len > 0)
			len--; /* drop the separator */
	}
	return tags;
}

/***
* A built `set`. Every lookup returns an integer tag, 0 when nothing matches.
* @type set
*/

/***
* Returns the tag of an exact member, or 0 if absent.
* @function has
* @tparam string s the member to look up.
* @treturn integer the member's tag, or 0.
*/
static int luaset_has(lua_State *L)
{
	luaset_t *set = luaset_check(L, 1);
	size_t len;
	const char *s = luaL_checklstring(L, 2, &len);
	int idx = luaset_find(set, s, (uint32_t)len);

	lua_pushinteger(L, idx >= 0 ? luaset_tag(set, idx) : 0);
	return 1;
}

#define LUASET_NEWMATCH(dir)							\
static int luaset_##dir(lua_State *L)						\
{										\
	luaset_t *set = luaset_check(L, 1);					\
	size_t len, seplen;							\
	const char *s = luaL_checklstring(L, 2, &len);				\
	const char *sep = luaL_checklstring(L, 3, &seplen);			\
	luaL_argcheck(L, seplen == 1, 3, "separator must be a single byte");	\
	lua_pushinteger(L, luaset_walk##dir(set, s, len, sep[0]));		\
	return 1;								\
}

/***
* Returns the union of the tags of `s` and its matching suffixes, or 0.
*
* Tests `s`, then each suffix after a `sep` (`"a.b.com"` tries `"a.b.com"`, `"b.com"`,
* `"com"`), ORing the tags of every level that is a member. Roots the hierarchy on the
* right, as for domains.
* @function suffix
* @tparam string s the string to test.
* @tparam string sep a one-byte separator.
* @treturn integer the union of the matching levels' tags, or 0.
*/
LUASET_NEWMATCH(suffix);

/***
* Returns the union of the tags of `s` and its matching prefixes, or 0.
*
* Tests `s`, then each prefix before a `sep` (`"/a/b/c"` tries `"/a/b/c"`, `"/a/b"`,
* `"/a"`), ORing the tags of every level that is a member. Roots the hierarchy on the
* left, as for paths.
* @function prefix
* @tparam string s the string to test.
* @tparam string sep a one-byte separator.
* @treturn integer the union of the matching levels' tags, or 0.
*/
LUASET_NEWMATCH(prefix);

/***
* Returns the number of members.
* @function __len
* @treturn integer the number of members.
*/
static int luaset_length(lua_State *L)
{
	luaset_t *set = luaset_check(L, 1);
	lua_pushinteger(L, (lua_Integer)set->n);
	return 1;
}

typedef struct luaset_member_s {
	const char *lstr;
	uint32_t len;
	uint32_t tag;
} luaset_member_t;

static int luaset_membercmp(const void *a, const void *b)
{
	const luaset_member_t *x = a, *y = b;
	return luaset_compare(x->lstr, x->len, y->lstr, y->len);
}

#define luaset_foreach(L, ix)	for (lua_pushnil(L); lua_next((L), (ix)) != 0; lua_pop((L), 1))

static uint32_t luaset_measure(lua_State *L, int ix, size_t *total)
{
	lua_Integer n = 0;

	*total = 0;
	luaset_foreach(L, ix) {
		size_t len;
		lua_Integer tag = lua_tointeger(L, -1);

		luaL_argcheck(L, lua_type(L, -2) == LUA_TSTRING, ix, "members must be strings");
		luaL_argcheck(L, lua_isinteger(L, -1) && tag >= 1 && tag <= U32_MAX, ix,
			"tags must be integers in [1, 2^32)");
		lua_tolstring(L, -2, &len);
		*total += len;
		n++;
	}
	luaL_argcheck(L, *total <= U32_MAX, ix, "set too large"); /* offsets are uint32 */
	return (uint32_t)n;
}

static void luaset_fill(lua_State *L, int ix, luaset_member_t *members)
{
	uint32_t i = 0;

	luaset_foreach(L, ix) {
		size_t len;
		members[i].lstr = lua_tolstring(L, -2, &len);
		members[i].len = (uint32_t)len;
		members[i].tag = (uint32_t)lua_tointeger(L, -1);
		i++;
	}
}

static void luaset_pack(uint32_t *off, char *blob, uint32_t *tags, const luaset_member_t *members, uint32_t n)
{
	size_t pos = 0;
	uint32_t i;

	for (i = 0; i < n; i++) {
		off[i] = (uint32_t)pos;
		if (members[i].len > 0)
			memcpy(blob + pos, members[i].lstr, members[i].len);
		tags[i] = members[i].tag;
		pos += members[i].len;
	}
}

static void luaset_build(lua_State *L, int ix, uint32_t *off, char *blob, uint32_t *tags, uint32_t n)
{
	/* scratch, not object-owned: release can't reach it, so a raise here leaks */
	luaset_member_t *members = lunatik_checkalloc(L, (size_t)n * sizeof(luaset_member_t));

	luaset_fill(L, ix, members);
	sort(members, (size_t)n, sizeof(luaset_member_t), luaset_membercmp, NULL);
	luaset_pack(off, blob, tags, members, n);
	lunatik_free(members);
}

static void luaset_release(void *private)
{
	luaset_t *set = (luaset_t *)private;
	lunatik_free(set->blob);
	lunatik_free(set->off);
	lunatik_free(set->tags);
}

/***
* Builds the set from a table of members, each with a tag bitmask.
*
* It allocates, so call it where it can sleep (a process-context runtime, or any
* runtime's load).
* @function new
* @tparam {[string]=integer} t the member/tag pairs; tags are in `[1, 2^32)`.
* @treturn set the built set.
* @raise Error on a non-string member, a tag outside `[1, 2^32)`, if the members
* exceed 4 GiB, or on allocation failure.
* @within set
* @usage local s = set.new({ ["a.b.c"] = 1, ["b.c"] = 2, ["c"] = 4 })
* local tags = s:suffix("a.b.c", ".")  --> 7, the union 1 | 2 | 4
*/
static int luaset_new(lua_State *L)
{
	size_t total = 0;

	luaL_checktype(L, 1, LUA_TTABLE);
	uint32_t n = luaset_measure(L, 1, &total);

	lunatik_object_t *object = lunatik_newobject(L, &luaset_class, sizeof(luaset_t), LUNATIK_OPT_NONE);
	luaset_t *set = (luaset_t *)object->private;
	set->n = n;

	uint32_t *off = lunatik_checkalloc(L, sizeof(uint32_t) * ((size_t)n + 1));
	set->off = off;
	off[n] = (uint32_t)total;
	if (n == 0) /* empty set: only the terminating offset */
		goto out;

	char *blob = NULL;
	if (total > 0) { /* all-empty members store no blob */
		blob = lunatik_checkalloc(L, total);
		set->blob = blob;
	}

	uint32_t *tags = lunatik_checkalloc(L, sizeof(uint32_t) * n);
	set->tags = tags;
	luaset_build(L, 1, off, blob, tags, n);
out:
	return 1; /* object */
}

static const luaL_Reg luaset_lib[] = {
	{"new", luaset_new},
	{NULL, NULL}
};

static const luaL_Reg luaset_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__len", luaset_length},
	{"has", luaset_has},
	{"suffix", luaset_suffix},
	{"prefix", luaset_prefix},
	{NULL, NULL}
};

LUNATIK_OPENER(set);
static const lunatik_class_t luaset_class = {
	.name = "set",
	.methods = luaset_mt,
	.release = luaset_release,
	.opener = luaopen_set,
	.opt = LUNATIK_OPT_SOFTIRQ,
};

LUNATIK_CLASSES(set, &luaset_class);
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

