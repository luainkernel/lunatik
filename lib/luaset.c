/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Compact, immutable set of short strings.
*
* A `set` stores a large collection of short strings, such as a domain
* blocklist, in two contiguous buffers: a sorted blob of the key bytes and an
* array of offsets into it. There is no per-entry allocation, hash node, or slab
* rounding, so the resident cost stays close to the raw key bytes (about
* `length + 4` bytes per key) instead of the 80 to 110 bytes per key paid by a
* Lua table or an `rcu` table.
*
* A set is built once, in process context, with `set.new`, and is read-only
* afterwards. Lookups (`set:has`) take no lock, allocate nothing, and create no
* Lua strings, so they are safe to call from softirq or atomic context. Build the
* set in a sleepable runtime and share it, for example through `lunatik._ENV`,
* with a softirq runtime that queries it.
*
* @module set
* @see rcu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/sort.h>
#include <linux/string.h>

#include <lunatik.h>

/*
* off has n+1 entries; key i is blob[off[i] .. off[i+1]). Keys are stored
* sorted, so lookup is a binary search.
*/
typedef struct luaset_s {
	uint32_t n;
	const uint32_t *off;
	const char *blob;
} luaset_t;

/* a key borrowed from the input array, with its length; sorted while building */
typedef struct luaset_elem_s {
	const char *key;
	uint32_t len;
} luaset_elem_t;

static int luaset_new(lua_State *L);
static const lunatik_class_t luaset_class;

LUNATIK_PRIVATECHECKER(luaset_check, luaset_t *);

/* orders two byte strings; on a shared prefix, the shorter one sorts first */
static inline int luaset_keycmp(const char *a, uint32_t alen, const char *b, uint32_t blen)
{
	uint32_t m = min(alen, blen);
	int c = memcmp(a, b, m);
	if (c != 0)
		return c;
	return (alen > blen) - (alen < blen);
}

static bool luaset_contains(const luaset_t *set, const char *key, uint32_t len)
{
	int lo = 0, hi = (int)set->n - 1;

	while (lo <= hi) {
		int mid = lo + (hi - lo) / 2;
		const char *k = set->blob + set->off[mid];
		uint32_t klen = set->off[mid + 1] - set->off[mid];
		int c = luaset_keycmp(key, len, k, klen);

		if (c == 0)
			return true;
		if (c < 0)
			hi = mid - 1;
		else
			lo = mid + 1;
	}
	return false;
}

/* true if s, or a suffix of it that begins after a sep byte, is a member */
static bool luaset_find(const luaset_t *set, const char *s, size_t len, char sep)
{
	size_t i = 0;

	while (i <= len) {
		if (luaset_contains(set, s + i, (uint32_t)(len - i)))
			return true;
		const char *next = memchr(s + i, sep, len - i);
		if (next == NULL)
			return false;
		i = (size_t)(next - s) + 1;
	}
	return false;
}

/***
* An immutable set of strings, created by `set.new`. Test a string against it
* with `set:has` and read its size with the `#` operator.
* @type set
*/

/***
* Tests a string for membership, optionally by suffix.
*
* With no `sep` the test is exact. With a single-byte `sep` it also accepts any
* suffix of `s` that begins right after a `sep`, so `set:has("a.b.com", ".")`
* tries `"a.b.com"`, then `"b.com"`, then `"com"`. That is how a domain blocklist
* covers subdomains.
* @function has
* @tparam string s the string to test.
* @tparam[opt] string sep a one-byte separator; omit to test `s` exactly.
* @treturn boolean whether `s`, or a suffix of it, is in the set.
* @usage
*   blocked:has("ads.example.com")       -- exact
*   blocked:has("ads.example.com", ".")   -- also tries example.com, com
*/
static int luaset_has(lua_State *L)
{
	luaset_t *set = luaset_check(L, 1);
	size_t len, seplen;
	const char *s = luaL_checklstring(L, 2, &len);
	const char *sep = luaL_optlstring(L, 3, NULL, &seplen);
	bool found;

	if (sep == NULL)
		found = luaset_contains(set, s, (uint32_t)len);
	else {
		luaL_argcheck(L, seplen == 1, 3, "separator must be a single byte");
		found = luaset_find(set, s, len, sep[0]);
	}
	lua_pushboolean(L, found);
	return 1;
}

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

static int luaset_elemcmp(const void *a, const void *b)
{
	const luaset_elem_t *x = a, *y = b;
	return luaset_keycmp(x->key, x->len, y->key, y->len);
}

/*
* Sorts the n keys, then allocates the blob and offsets and writes them in.
* Returns false on allocation failure, after freeing whatever it allocated.
*/
static bool luaset_build(lua_State *L, luaset_t *set, luaset_elem_t *elem, uint32_t n)
{
	uint32_t i, used = 0;
	size_t bytes = 0;
	char *blob;
	uint32_t *off;

	sort(elem, n, sizeof(*elem), luaset_elemcmp, NULL);
	for (i = 0; i < n; i++)
		bytes += elem[i].len;

	blob = lunatik_malloc(L, bytes ? bytes : 1); /* lunatik_malloc(0) frees */
	off = lunatik_malloc(L, sizeof(uint32_t) * (n + 1));
	if (blob == NULL || off == NULL) {
		lunatik_free(blob);
		lunatik_free(off);
		return false;
	}

	for (i = 0; i < n; i++) {
		off[i] = used;
		memcpy(blob + used, elem[i].key, elem[i].len);
		used += elem[i].len;
	}
	off[n] = used;
	set->blob = blob;
	set->off = off;
	set->n = n;
	return true;
}

static void luaset_release(void *private)
{
	luaset_t *set = (luaset_t *)private;
	lunatik_free(set->blob);
	lunatik_free(set->off);
}

/***
* Builds an immutable set from an array of strings.
*
* The array's strings become the members and are sorted for lookup. Pass unique
* strings: a repeated string is stored more than once, which keeps lookups
* correct but inflates `#set` and wastes memory. The build allocates, so call it
* from a process-context (sleepable) runtime; the set is then shareable with a
* softirq runtime, such as a netfilter or XDP hook, which queries it with
* `set:has`.
* @function new
* @tparam {string,...} strings the member strings.
* @treturn set the set.
* @raise Error on allocation failure.
* @within set
* @usage local blocked = set.new({ "evil.com", "ads.net", "tracker.io" })
*/
static int luaset_new(lua_State *L)
{
	lunatik_object_t *object;
	luaset_t *set;
	lua_Integer cap;

	luaL_checktype(L, 1, LUA_TTABLE);
	lunatik_checkruntime(L, LUNATIK_OPT_NONE); /* build is process-context only */

	object = lunatik_newobject(L, &luaset_class, sizeof(luaset_t), LUNATIK_OPT_NONE);
	set = (luaset_t *)object->private;

	/* an empty array leaves the object's zeroed (empty) private as is */
	cap = (lua_Integer)lua_rawlen(L, 1);
	if (cap > 0) {
		luaset_elem_t *elem = lunatik_checkalloc(L, sizeof(*elem) * (size_t)cap);
		uint32_t n = 0;
		lua_Integer i;

		for (i = 1; i <= cap; i++) {
			if (lua_rawgeti(L, 1, i) == LUA_TSTRING) {
				size_t len;
				elem[n].key = lua_tolstring(L, -1, &len);
				elem[n].len = (uint32_t)len;
				n++;
			}
			lua_pop(L, 1);
		}

		bool ok = luaset_build(L, set, elem, n);
		lunatik_free(elem);
		if (!ok)
			lunatik_enomem(L);
	}
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

