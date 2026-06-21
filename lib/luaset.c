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
* `set.new` builds a plain set, tested for exact membership with `set:has`: a single
* binary search, `O(log n)`.
* `set.labeled` builds a labeled set: each member carries a 32-bit label bitmask, and
* `set:match` walks a key by `.` returning the bitwise OR of the labels of every member
* that is a suffix of it (0 when nothing matches); one binary search per `.`-separated
* level, `O(d log n)` for a `d`-level key.
*
* @module set
* @see rcu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/string.h>
#include <linux/sort.h>

#include <lunatik.h>

#define LUASET_SEP	'.'

typedef struct luaset_s {
	size_t n;		/* number of members */
	const uint32_t *off;	/* n+1 offsets into blob */
	const char *blob;	/* sorted members concatenated, no separator */
	const uint32_t *labels;	/* NULL for a plain set; per-member labels when labeled */
} luaset_t;

static int luaset_new(lua_State *L);
static int luaset_labeled(lua_State *L);
static const lunatik_class_t luaset_class;
static const lunatik_class_t luaset_labeled_class;

LUNATIK_PRIVATECHECKER(luaset_check, luaset_t *);

static inline int luaset_keycmp(const char *a, uint32_t alen, const char *b, uint32_t blen)
{
	uint32_t m = min(alen, blen);
	int c = memcmp(a, b, m);
	return c != 0 ? c : (alen > blen) - (alen < blen);
}

static ssize_t luaset_find(const luaset_t *set, const char *s, uint32_t len)
{
	ssize_t lo = 0, hi = (ssize_t)set->n - 1;

	while (lo <= hi) {
		ssize_t mid = lo + (hi - lo) / 2;
		const char *member = set->blob + set->off[mid];
		uint32_t mlen = set->off[mid + 1] - set->off[mid];
		int c = luaset_keycmp(s, len, member, mlen);

		if (c == 0)
			return mid;
		if (c < 0)
			hi = mid - 1;
		else
			lo = mid + 1;
	}
	return -1;
}

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

static void luaset_release(void *private)
{
	luaset_t *set = (luaset_t *)private;
	lunatik_free(set->blob);
	lunatik_free(set->off);
	lunatik_free(set->labels);
}

/***
* A built plain `set`, returned by `set.new`.
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
* @usage local s = set.new({ "alpha", "bravo" })
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

static uint32_t luaset_walk(const luaset_t *set, const char *s, size_t len)
{
	uint32_t labels = 0;
	size_t i = 0;

	while (i <= len) {
		ssize_t idx = luaset_find(set, s + i, (uint32_t)(len - i));
		if (idx >= 0)
			labels |= set->labels[idx];
		const char *next = memchr(s + i, LUASET_SEP, len - i);
		if (next == NULL)
			break;
		i = (size_t)(next - s) + 1;
	}
	return labels;
}

/***
* A built labeled `set`, returned by `set.labeled`.
* @type set.labeled
*/

/***
* Returns the union of the labels of `s` and its suffixes, or 0.
*
* Walks `s` by `.` (`"a.b.c"` tries `"a.b.c"`, `"b.c"`, `"c"`), ORing the labels of
* every level that is a member. This roots the hierarchy on the right.
* @function match
* @tparam string s the string to look up.
* @treturn integer the union of the matching levels' labels, or 0.
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
	uint32_t label;
} luaset_member_t;

static int luaset_membercmp(const void *a, const void *b)
{
	const luaset_member_t *x = a, *y = b;
	return luaset_keycmp(x->lstr, x->len, y->lstr, y->len);
}

#define luaset_foreach(L, ix)	for (lua_pushnil(L); lua_next((L), (ix)) != 0; lua_pop((L), 1))

static size_t luaset_count(lua_State *L, int ix, size_t *total)
{
	lua_Integer n = 0;

	*total = 0;
	luaset_foreach(L, ix) {
		size_t len;
		lua_Integer label = lua_tointeger(L, -1);

		luaL_argcheck(L, lua_type(L, -2) == LUA_TSTRING, ix, "members must be strings");
		luaL_argcheck(L, lua_isinteger(L, -1) && label >= 1 && label <= U32_MAX, ix,
			"labels must be integers in [1, 2^32)");
		lua_tolstring(L, -2, &len);
		*total += len;
		n++;
	}
	luaL_argcheck(L, *total <= U32_MAX, ix, "table too large"); /* offsets are uint32 */
	return (size_t)n;
}

static luaset_member_t *luaset_load(lua_State *L, int ix, size_t n)
{
	luaset_member_t *members = lunatik_checkalloc(L, n * sizeof(luaset_member_t));
	size_t i = 0;

	luaset_foreach(L, ix) {
		size_t len;
		members[i].lstr = lua_tolstring(L, -2, &len);
		members[i].len = (uint32_t)len;
		members[i].label = (uint32_t)lua_tointeger(L, -1);
		i++;
	}
	return members;
}

static void luaset_store(uint32_t *off, char *blob, uint32_t *labels, const luaset_member_t *members, size_t n)
{
	size_t pos = 0;
	size_t i;

	for (i = 0; i < n; i++) {
		off[i] = (uint32_t)pos;
		if (members[i].len > 0)
			memcpy(blob + pos, members[i].lstr, members[i].len);
		labels[i] = members[i].label;
		pos += members[i].len;
	}
}

/***
* Builds a labeled set from a table of members, each with a label bitmask.
*
* It allocates, so call it where it can sleep (a process-context runtime, or any
* runtime's load).
* @function labeled
* @tparam {[string]=integer} t the member/labels pairs; labels are in `[1, 2^32)`.
* @treturn set.labeled the built labeled set.
* @raise Error on a non-string member, a label outside `[1, 2^32)`, if the members
* exceed 4 GiB, or on allocation failure.
* @usage local s = set.labeled({ ["a.b.c"] = 1, ["b.c"] = 2, ["c"] = 4 })
* local labels = s:match("a.b.c")  --> 7, the union 1 | 2 | 4
*/
static int luaset_labeled(lua_State *L)
{
	size_t total = 0;

	luaL_checktype(L, 1, LUA_TTABLE);
	size_t n = luaset_count(L, 1, &total);

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

	uint32_t *labels = lunatik_checkalloc(L, sizeof(uint32_t) * n);
	set->labels = labels;

	luaset_member_t *members = luaset_load(L, 1, n);
	sort(members, n, sizeof(luaset_member_t), luaset_membercmp, NULL);
	luaset_store(off, blob, labels, members, n);
	lunatik_free(members);
out:
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

static const luaL_Reg luaset_labeled_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__len", luaset_length},
	{"match", luaset_match},
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

static const lunatik_class_t luaset_labeled_class = {
	.name = "set.labeled",
	.methods = luaset_labeled_mt,
	.release = luaset_release,
	.opt = LUNATIK_OPT_SOFTIRQ,
};

LUNATIK_CLASSES(set, &luaset_class, &luaset_labeled_class);
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

