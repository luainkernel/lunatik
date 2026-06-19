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
* Built once by `set.new` (which sorts the members), it is then read-only: lookups
* take no lock and allocate nothing, safe from softirq. It tests exact membership
* (`set:has`) or matches by segment, from the right (`set:suffix`, as for domains)
* or the left (`set:prefix`, as for filesystem or URI paths).
*
* A set may also carry a per-key integer **label**: built from a `{key = integer}`
* map instead of an array, it packs the labels in a parallel fixed-width column
* (the smallest of 1, 2, 4 or 8 bytes that holds the largest label, no offsets),
* and the same lookups return the matched key's label instead of a boolean. This
* turns a `set` into a compact key-to-small-integer map, e.g. a domain to a bitmask
* of categories, queried in the hot path with no allocation.
*
* @module set
* @see rcu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/string.h>
#include <asm/byteorder.h>

#include <lunatik.h>

typedef struct luaset_s {
	uint32_t n;		/* number of keys */
	const uint32_t *off;	/* n+1 offsets into blob */
	const char *blob;	/* all keys concatenated, no separator */
	const void *labels;	/* NULL when unlabeled; else n labels of `width` bytes */
	uint8_t width;		/* label width in bytes (0 = unlabeled, returns a boolean) */
} luaset_t;

static int luaset_new(lua_State *L);
static const lunatik_class_t luaset_class;

LUNATIK_PRIVATECHECKER(luaset_check, luaset_t *);

static inline int luaset_keycmp(const char *a, uint32_t alen, const char *b, uint32_t blen)
{
	uint32_t m = min(alen, blen);
	int c = memcmp(a, b, m);
	return c != 0 ? c : (alen > blen) - (alen < blen);
}

static int luaset_find(const luaset_t *set, const char *key, uint32_t len)
{
	int lo = 0, hi = (int)set->n - 1;

	while (lo <= hi) {
		int mid = lo + (hi - lo) / 2;
		const char *k = set->blob + set->off[mid];
		uint32_t klen = set->off[mid + 1] - set->off[mid];
		int c = luaset_keycmp(key, len, k, klen);

		if (c == 0)
			return mid;
		if (c < 0)
			hi = mid - 1;
		else
			lo = mid + 1;
	}
	return -1;
}

static int luaset_findsuffix(const luaset_t *set, const char *s, size_t len, char sep)
{
	size_t i = 0;

	while (i <= len) {
		int idx = luaset_find(set, s + i, (uint32_t)(len - i));
		if (idx >= 0)
			return idx;
		const char *next = memchr(s + i, sep, len - i);
		if (next == NULL)
			return -1;
		i = (size_t)(next - s) + 1;
	}
	return -1;
}

static int luaset_findprefix(const luaset_t *set, const char *s, size_t len, char sep)
{
	while (len > 0) {
		int idx = luaset_find(set, s, (uint32_t)len);
		if (idx >= 0)
			return idx;
		while (len > 0 && s[len - 1] != sep)
			len--;
		if (len > 0)
			len--; /* drop the separator */
	}
	return -1;
}

static lua_Integer luaset_label(const luaset_t *set, int idx)
{
	uint64_t le = 0;
	memcpy(&le, (const char *)set->labels + (size_t)idx * set->width, set->width);
	return (lua_Integer)le64_to_cpu(le);
}

static int luaset_result(lua_State *L, const luaset_t *set, int idx)
{
	if (set->width == 0)
		lua_pushboolean(L, idx >= 0);
	else if (idx < 0)
		lua_pushnil(L);
	else
		lua_pushinteger(L, luaset_label(set, idx));
	return 1;
}

/***
* A built `set`. Query it with `set:has` for exact membership, `set:suffix` or
* `set:prefix` for segment membership, and `#` for size. On a labeled set the same
* methods return the matched key's integer label, or nil when there is no match.
* @type set
*/

/***
* Tests an exact key.
* @function has
* @tparam string s the string to test.
* @treturn boolean|integer|nil whether `s` is in the set; or its label, or nil if absent, when labeled.
*/
static int luaset_has(lua_State *L)
{
	luaset_t *set = luaset_check(L, 1);
	size_t len;
	const char *s = luaL_checklstring(L, 2, &len);

	return luaset_result(L, set, luaset_find(set, s, (uint32_t)len));
}

#define LUASET_NEWMATCH(dir)							\
static int luaset_##dir(lua_State *L)						\
{										\
	luaset_t *set = luaset_check(L, 1);					\
	size_t len, seplen;							\
	const char *s = luaL_checklstring(L, 2, &len);				\
	const char *sep = luaL_checklstring(L, 3, &seplen);			\
	luaL_argcheck(L, seplen == 1, 3, "separator must be a single byte");	\
	return luaset_result(L, set, luaset_find##dir(set, s, len, sep[0]));	\
}

/***
* Matches `s`, or a suffix of it after a separator, against the set.
*
* Tests `s`, then each suffix starting after a `sep`, so `t:suffix("a.b.com", ".")`
* tries `"a.b.com"`, `"b.com"`, `"com"`. This roots the hierarchy on the right, as
* for domains, reverse-DNS, or dotted ids.
* @function suffix
* @tparam string s the string to test.
* @tparam string sep a one-byte separator.
* @treturn boolean|integer|nil whether a suffix is in the set; or its label, or nil, when labeled.
*/
LUASET_NEWMATCH(suffix);

/***
* Matches `s`, or a prefix of it before a separator, against the set.
*
* Tests `s`, then each prefix ending before a `sep`, so `t:prefix("/a/b/c", "/")`
* tries `"/a/b/c"`, `"/a/b"`, `"/a"`. This roots the hierarchy on the left, as for
* filesystem or URI paths.
* @function prefix
* @tparam string s the string to test.
* @tparam string sep a one-byte separator.
* @treturn boolean|integer|nil whether a prefix is in the set; or its label, or nil, when labeled.
*/
LUASET_NEWMATCH(prefix);

/***
* Returns the number of keys in the set.
* @function __len
* @treturn integer the number of keys.
*/
static int luaset_length(lua_State *L)
{
	luaset_t *set = luaset_check(L, 1);
	lua_pushinteger(L, (lua_Integer)set->n);
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

static void luaset_collect(lua_State *L)
{
	lua_Integer i = 0;

	lua_newtable(L); /* sorted-key array at index 2 */
	lua_pushnil(L);
	while (lua_next(L, 1) != 0) {
		lua_pushvalue(L, -2);	/* duplicate the key */
		lua_rawseti(L, 2, ++i);
		lua_pop(L, 1);		/* drop the value, keep the key for lua_next */
	}
	luaset_sort(L, 2);
}

static size_t luaset_measure(lua_State *L, int kidx, uint32_t *off, lua_Integer n)
{
	lua_Integer i;
	size_t total = 0;

	for (i = 1; i <= n; i++) {
		luaL_argcheck(L, lua_rawgeti(L, kidx, i) == LUA_TSTRING, 1, "keys must be strings");
		off[i - 1] = (uint32_t)total;
		total += lua_rawlen(L, -1);
		luaL_argcheck(L, total <= U32_MAX, 1, "set too large"); /* offsets are uint32 */
		lua_pop(L, 1);
	}
	off[n] = (uint32_t)total;
	return total;
}

static void luaset_pack(lua_State *L, int kidx, char *blob, const uint32_t *off, lua_Integer n)
{
	lua_Integer i;

	for (i = 1; i <= n; i++) {
		size_t len;
		const char *s;

		lua_rawgeti(L, kidx, i);
		s = lua_tolstring(L, -1, &len);
		memcpy(blob + off[i - 1], s, len);
		lua_pop(L, 1);
	}
}

static uint8_t luaset_width(lua_Integer max)
{
	if ((uint64_t)max <= U8_MAX)
		return 1;
	if ((uint64_t)max <= U16_MAX)
		return 2;
	if ((uint64_t)max <= U32_MAX)
		return 4;
	return 8;
}

static lua_Integer luaset_labelmax(lua_State *L, lua_Integer n)
{
	lua_Integer i, max = 0;

	for (i = 1; i <= n; i++) {
		lua_Integer v;
		lua_rawgeti(L, 2, i);
		lua_rawget(L, 1);
		v = lua_tointeger(L, -1);
		luaL_argcheck(L, lua_isinteger(L, -1) && v >= 0, 1, "labels must be non-negative integers");
		if (v > max)
			max = v;
		lua_pop(L, 1);
	}
	return max;
}

static void luaset_packlabels(lua_State *L, lua_Integer n, void *labels, uint8_t width)
{
	lua_Integer i;

	for (i = 1; i <= n; i++) {
		uint64_t le;

		lua_rawgeti(L, 2, i);
		lua_rawget(L, 1);
		le = cpu_to_le64((uint64_t)lua_tointeger(L, -1));
		memcpy((char *)labels + (size_t)(i - 1) * width, &le, width);
		lua_pop(L, 1);
	}
}

static void luaset_buildkeys(lua_State *L, luaset_t *set, int kidx, lua_Integer n)
{
	size_t total;
	char *blob;
	uint32_t *off = lunatik_malloc(L, sizeof(uint32_t) * (n + 1));

	if (off == NULL)
		lunatik_enomem(L);
	set->off = off; /* own off before measure can raise, so release frees it */
	set->n = (uint32_t)n;

	total = luaset_measure(L, kidx, off, n);
	if (total == 0) /* no bytes to store; lookups never read blob */
		return;

	blob = lunatik_malloc(L, total);
	if (blob == NULL)
		lunatik_enomem(L);
	set->blob = blob;
	luaset_pack(L, kidx, blob, off, n);
}

static void luaset_buildlabels(lua_State *L, luaset_t *set, lua_Integer n)
{
	uint8_t width = luaset_width(luaset_labelmax(L, n));
	void *labels = lunatik_malloc(L, (size_t)n * width);

	if (labels == NULL)
		lunatik_enomem(L);
	set->labels = labels;
	set->width = width;
	luaset_packlabels(L, n, labels, width);
}

static void luaset_release(void *private)
{
	luaset_t *set = (luaset_t *)private;
	lunatik_free(set->blob);
	lunatik_free(set->off);
	lunatik_free(set->labels);
}

/***
* Builds the set from an array of strings, or a map of strings to integers.
*
* An array `{"a", "b"}` builds a membership set whose lookups return a boolean. A
* map `{a = 1, b = 2}` builds a labeled set whose lookups return the matched key's
* integer label (the smallest of 1/2/4/8 bytes is used per label). The keys are
* sorted; duplicates in the array form are kept (correct but wasteful, so
* de-duplicate first if it matters). It allocates, so call it where it can sleep (a
* process-context runtime, or any runtime's load).
* @function new
* @tparam {string,...}|{[string]=integer} t the members, or the key/label pairs.
* @treturn set the built set.
* @raise Error on a non-string key, a non-integer or negative label, if the keys
* exceed 4 GiB, or on allocation failure.
* @within set
* @usage local blocked = set.new({ "evil.com", "ads.net" })
* @usage local category = set.new({ ["evil.com"] = 1, ["casino.bet"] = 2 })
*/
static int luaset_new(lua_State *L)
{
	lunatik_object_t *object;
	luaset_t *set;
	int labeled;

	luaL_checktype(L, 1, LUA_TTABLE);
	labeled = lua_rawgeti(L, 1, 1) != LUA_TSTRING; /* an array's [1] is a string, a map's is nil */
	lua_pop(L, 1);

	if (labeled)
		luaset_collect(L); /* map at index 1 -> sorted keys at index 2 */
	else
		luaset_sort(L, 1);

	object = lunatik_newobject(L, &luaset_class, sizeof(luaset_t), LUNATIK_OPT_NONE);
	set = (luaset_t *)object->private;

	if (!labeled) {
		luaset_buildkeys(L, set, 1, (lua_Integer)lua_rawlen(L, 1));
		return 1; /* object */
	}

	lua_Integer n = (lua_Integer)lua_rawlen(L, 2);
	luaset_buildkeys(L, set, 2, n);
	if (n > 0) /* an empty map stays unlabeled (width 0); there is nothing to label */
		luaset_buildlabels(L, set, n);
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

