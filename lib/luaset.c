/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* A `set` is a compact, immutable set of strings, queried by binary search.
*
* It stores many short strings as a sorted blob of key bytes plus a uint32 offset
* array, with no per-key allocation, so it costs about `length + 4` bytes per key,
* and 4 more for a label, instead of the hash node and slab rounding a Lua or `rcu`
* table pays per key. Built once, it is then read-only: lookups take no lock and
* allocate nothing, safe from softirq.
*
* `set:has` tests exact membership: a single binary search, `O(log n)`.
* `set:match` walks a key by `.` and returns the label of the longest member the key
* ends in at a level (0 when nothing matches); one binary search per `.`-separated level,
* `O(d log n)` for a `d`-level key.
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
	const uint32_t *labels;	/* per-member labels of a map; NULL for a list, whose members carry 1 */
} luaset_t;

static const lunatik_class_t luaset_class;

LUNATIK_PRIVATECHECKER(luaset_check, luaset_t *, &luaset_class);

static inline int luaset_keycmp(const char *a, size_t alen, const char *b, size_t blen)
{
	size_t m = min(alen, blen);
	int c = memcmp(a, b, m);
	return c != 0 ? c : (alen > blen) - (alen < blen);
}

static ssize_t luaset_find(const luaset_t *set, const char *s, size_t len)
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
* A built `set`, returned by `set.new`; `#s` is its number of members.
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

	lua_pushboolean(L, luaset_find(set, s, len) >= 0);
	return 1;
}

static uint32_t luaset_walk(const luaset_t *set, const char *s, size_t len)
{
	size_t i = 0;

	while (i <= len) {
		ssize_t idx = luaset_find(set, s + i, len - i);
		if (idx >= 0)
			return set->labels != NULL ? set->labels[idx] : 1;
		const char *next = memchr(s + i, LUASET_SEP, len - i);
		if (next == NULL)
			break;
		i = (size_t)(next - s) + 1;
	}
	return 0;
}

/***
* Returns the label of the longest member `s` ends in at a level, or 0.
*
* Walks `s` by `.` (`"a.b.c"` tries `"a.b.c"`, `"b.c"`, `"c"`) and stops at the first
* level that is a member, so the most specific member decides. This roots the
* hierarchy on the right.
* @function match
* @tparam string s the string to look up.
* @treturn integer the label of the longest matching level, or 0.
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

#define luaset_memberix(map)	((map) ? -2 : -1) /* a map's member is the key, a list's the value */

static size_t luaset_count(lua_State *L, int ix, bool map, size_t *total)
{
	size_t n = 0;

	*total = 0;
	luaset_foreach(L, ix) {
		size_t len;
		lua_Integer label = lua_tointeger(L, -1);

		luaL_argcheck(L, map || lua_type(L, -2) == LUA_TNUMBER, ix, "a list and a map mixed");
		luaL_argcheck(L, lua_type(L, luaset_memberix(map)) == LUA_TSTRING, ix, "members must be strings");
		luaL_argcheck(L, !map || (lua_type(L, -1) == LUA_TNUMBER && label >= 1 && label <= U32_MAX), ix,
			"labels must be integers in [1, 2^32)");
		lua_tolstring(L, luaset_memberix(map), &len);
		*total += len;
		n++;
	}
	luaL_argcheck(L, *total <= U32_MAX, ix, "table too large"); /* offsets are uint32 */
	return n;
}

static luaset_member_t *luaset_load(lua_State *L, int ix, bool map, size_t n)
{
	luaset_member_t *members = lunatik_checkalloc(L, n * sizeof(luaset_member_t));
	size_t i = 0;

	luaset_foreach(L, ix) {
		size_t len;
		members[i].lstr = lua_tolstring(L, luaset_memberix(map), &len);
		members[i].len = (uint32_t)len;
		members[i].label = (uint32_t)lua_tointeger(L, -1);
		i++;
	}
	return members;
}

static size_t luaset_unique(luaset_member_t *members, size_t n)
{
	size_t m = 1;
	size_t i;

	for (i = 1; i < n; i++)
		if (luaset_membercmp(&members[m - 1], &members[i]) != 0)
			members[m++] = members[i];
	return m;
}

static void luaset_store(uint32_t *off, char *blob, uint32_t *labels, const luaset_member_t *members, size_t n)
{
	size_t pos = 0;
	size_t i;

	for (i = 0; i < n; i++) {
		off[i] = (uint32_t)pos;
		if (members[i].len > 0)
			memcpy(blob + pos, members[i].lstr, members[i].len);
		if (labels != NULL)
			labels[i] = members[i].label;
		pos += members[i].len;
	}
	off[n] = (uint32_t)pos;
}

static void luaset_build(lua_State *L, int ix, luaset_t *set, bool map, size_t n, size_t total)
{
	if (n == 0) /* the empty set allocates nothing: a search over no members reads no offset */
		return;

	uint32_t *off = lunatik_checkalloc(L, sizeof(uint32_t) * (n + 1));
	set->off = off;

	char *blob = NULL;
	if (total > 0) { /* all-empty members store no blob */
		blob = lunatik_checkalloc(L, total);
		set->blob = blob;
	}

	uint32_t *labels = NULL;
	if (map) {
		labels = lunatik_checkalloc(L, sizeof(uint32_t) * n);
		set->labels = labels;
	}

	luaset_member_t *members = luaset_load(L, ix, map, n);
	sort(members, n, sizeof(luaset_member_t), luaset_membercmp, NULL);
	set->n = luaset_unique(members, n); /* a list's duplicates count once */
	luaset_store(off, blob, labels, members, set->n);
	lunatik_free(members);
}

/***
* Builds a set from a list of strings or from a map of strings to labels.
*
* A label is an integer in `[1, 2^32)`, which `match` returns; the members of a list
* carry 1, and a list's duplicates count once. It allocates, so call it where it can
* sleep (a process-context runtime, or any runtime's load).
* @function new
* @tparam table t the members, as a list of strings or as a map from each member to its label.
* @treturn set the built set.
* @raise Error on a non-string member, a label outside `[1, 2^32)`, a list and a map
* mixed, if the members exceed 4 GiB, or on allocation failure.
* @usage local allowed = set.new({ "alpha", "bravo" })
* local policy = set.new({ ["go.com"] = 7, ["abcnews.go.com"] = 9 })
* local label = policy:match("www.abcnews.go.com")  --> 9, the longest member decides
* @within set
*/
static int luaset_new(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TTABLE);
	bool map = lua_rawlen(L, 1) == 0; /* an empty table builds the empty set either way */
	/* before count and load read the table: allocating may run a __gc that changes it between them */
	lunatik_object_t *object = lunatik_newobject(L, &luaset_class, sizeof(luaset_t), LUNATIK_OPT_NONE);
	size_t total;
	size_t n = luaset_count(L, 1, map, &total);

	luaset_build(L, 1, (luaset_t *)object->private, map, n, total);
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
	{"match", luaset_match},
	{NULL, NULL}
};

static const lunatik_class_t luaset_class = {
	.name = "set",
	.methods = luaset_mt,
	.release = luaset_release,
	.opt = LUNATIK_OPT_SOFTIRQ,
	.owner = THIS_MODULE,
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
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_DESCRIPTION("Lunatik immutable string set");

