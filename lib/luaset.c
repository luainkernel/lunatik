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
#include <linux/kernel_read_file.h>

#include <lunatik.h>

#define LUASET_SEP	'.'

#define LUASET_MAGIC	"LSET"
#define LUASET_VERSION	1
#define LUASET_LABELED	0x1

typedef struct luaset_s {
	size_t n;		/* number of members */
	const uint32_t *off;	/* n+1 offsets into blob */
	const char *blob;	/* sorted members concatenated, no separator */
	const uint32_t *labels;	/* per-member labels of a map; NULL for a list, whose members carry 1 */
	void *buf;		/* the one allocation off, labels and blob point into */
} luaset_t;

static const lunatik_class_t luaset_class;

LUNATIK_PRIVATECHECKER(luaset_check, luaset_t *, &luaset_class);

static inline int luaset_keycmp(const char *a, uint32_t alen, const char *b, uint32_t blen)
{
	uint32_t m = min(alen, blen);
	int c = memcmp(a, b, m);
	return c != 0 ? c : (alen > blen) - (alen < blen);
}

#define luaset_key(set, i)	((set)->blob + (set)->off[(i)])
#define luaset_keylen(set, i)	((set)->off[(i) + 1] - (set)->off[(i)])

static ssize_t luaset_find(const luaset_t *set, const char *s, uint32_t len)
{
	ssize_t lo = 0, hi = (ssize_t)set->n - 1;

	while (lo <= hi) {
		ssize_t mid = lo + (hi - lo) / 2;
		int c = luaset_keycmp(s, len, luaset_key(set, mid), luaset_keylen(set, mid));

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
	lunatik_free(set->buf);
}

/***
* A built `set`, returned by `set.new` or `set.load`; `#s` is its number of members.
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

static uint32_t luaset_walk(const luaset_t *set, const char *s, size_t len)
{
	size_t i = 0;

	while (i <= len) {
		ssize_t idx = luaset_find(set, s + i, (uint32_t)(len - i));
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
	lua_Integer n = 0;

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
	return (size_t)n;
}

static luaset_member_t *luaset_collect(lua_State *L, int ix, bool map, size_t n)
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

static void luaset_build(lua_State *L, luaset_t *set, bool map, size_t n, size_t total)
{
	size_t words = n + 1 + (map ? n : 0);
	uint32_t *off = lunatik_checkalloc(L, sizeof(uint32_t) * words + total);
	set->buf = off;
	set->off = off;
	off[0] = 0;
	if (n == 0) /* empty set: only the terminating offset */
		return;

	char *blob = (char *)(off + words);
	set->blob = blob;

	uint32_t *labels = map ? off + n + 1 : NULL;
	set->labels = labels;

	luaset_member_t *members = luaset_collect(L, 1, map, n);
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

	luaset_build(L, (luaset_t *)object->private, map, n, total);
	return 1; /* object */
}

typedef struct luaset_header_s {
	char magic[4];
	__le16 version;
	__le16 flags;
	__le32 n;		/* number of members */
	__le32 len;		/* bytes of blob */
} luaset_header_t;

#define luaset_isordered(set, i)	\
	(luaset_keycmp(luaset_key(set, (i) - 1), luaset_keylen(set, (i) - 1), luaset_key(set, i), luaset_keylen(set, i)) < 0)

static const char *luaset_verify(const luaset_t *set, uint32_t len)
{
	size_t i;

	if (set->off[0] != 0 || set->off[set->n] != len)
		return "offsets out of bounds";
	for (i = 0; i < set->n; i++) {
		if (set->off[i] > set->off[i + 1])
			return "offsets out of order";
		if (set->labels != NULL && set->labels[i] == 0)
			return "label outside [1, 2^32)";
	}
	for (i = 1; i < set->n; i++)
		if (!luaset_isordered(set, i))
			return "unsorted or repeated members";
	return NULL;
}

static const char *luaset_parse(luaset_t *set, void *buf, size_t size)
{
	luaset_header_t *header = (luaset_header_t *)buf;

	if (size < sizeof(luaset_header_t) || memcmp(header->magic, LUASET_MAGIC, sizeof(header->magic)) != 0)
		return "not a set file";
	if (le16_to_cpu(header->version) != LUASET_VERSION)
		return "unsupported version";

	uint16_t flags = le16_to_cpu(header->flags);
	if ((flags & ~LUASET_LABELED) != 0)
		return "unknown flags";

	bool labeled = flags & LUASET_LABELED;
	size_t n = le32_to_cpu(header->n);
	uint32_t len = le32_to_cpu(header->len);
	uint64_t words = (uint64_t)n + 1 + (labeled ? n : 0);
	if (size - sizeof(luaset_header_t) != words * sizeof(uint32_t) + len)
		return "size mismatch";

	uint32_t *off = (uint32_t *)(header + 1);
	size_t i;
	for (i = 0; i < words; i++)
		le32_to_cpus(&off[i]); /* the set reads them in place; a no-op on little-endian */

	set->n = n;
	set->off = off;
	set->labels = labeled ? off + n + 1 : NULL;
	set->blob = (const char *)(off + words);
	return luaset_verify(set, len);
}

/***
* Builds a set from a file in the layout below, which a tool writes in userspace.
*
* The file is read whole, in one allocation that `maxbytes` bounds before it is made, and
* the set uses it in place: a set costs its file's size, and building it copies, sorts and
* indexes nothing. `has`, `match` and `#` answer what `set.new` answers over the same
* members and labels.
*
* The file is little-endian throughout:
*
* - a 16-byte header: the ASCII bytes `LSET`; a u16 version, 1; u16 flags, whose bit 0 says
*   the file carries labels and whose other bits are 0; a u32 `n`, the number of members;
*   and a u32 `len`, the bytes the members take;
* - u32 `off[n+1]`, member `i` being bytes `off[i]` up to `off[i+1]` of the members;
* - u32 `labels[n]`, only when bit 0 is set; the members of a file without labels carry 1;
* - the members, concatenated without separators in `len` bytes.
*
* Its size is exactly `16 + 4(n+1) + 4n + len`, the `4n` only with labels; `off[0]` is 0,
* `off[n]` is `len` and no offset is below the one before it; the members are strictly
* increasing, compared byte by byte with the shorter first on a tie, so sorted and unique;
* and every label is in `[1, 2^32)`. A file that breaks one raises and builds nothing. A
* later layout takes another version; this one reads version 1.
*
* The path is resolved by the calling task, as `bpf.hash` resolves one. Reading the file
* sleeps, so call it where it can sleep (a process-context runtime, or any runtime's load).
* @function load
* @tparam string path the file.
* @tparam integer maxbytes the largest file it reads, in bytes, from 1.
* @treturn set the built set.
* @raise Error `ENOENT`, `EACCES`, `EFBIG` for a file larger than `maxbytes`, `EINVAL` for an
* empty or non-regular file, `ETXTBSY` while the file is open for writing, the errno a
* security module refuses the read with, `not allowed once the runtime is armed` (its script
* body has returned) on an interrupt-context runtime, or `<path>: ` followed by the first
* rule the file breaks: `not a set file`, `unsupported version`, `unknown flags`,
* `size mismatch`, `offsets out of bounds`, `offsets out of order`,
* `label outside [1, 2^32)` or `unsorted or repeated members`.
* @usage local blocked = set.load("/etc/lunatik/blocked.set", 64 << 20)
* local label = blocked:match("ads.example.com")
* @within set
*/
static int luaset_load(lua_State *L)
{
	lunatik_checkarmed(L);
	const char *path = luaL_checkstring(L, 1);
	size_t maxbytes = (size_t)lunatik_checkinteger(L, 2, 1, SSIZE_MAX);
	lunatik_object_t *object = lunatik_newobject(L, &luaset_class, sizeof(luaset_t), LUNATIK_OPT_NONE);
	luaset_t *set = (luaset_t *)object->private;
	void *buf = NULL;
	ssize_t size;

	lunatik_tryret(L, size, kernel_read_file_from_path, path, 0, &buf, maxbytes, NULL, READING_UNKNOWN);
	const char *invalid = luaset_parse(set, buf, (size_t)size);
	if (invalid != NULL) {
		lunatik_free(buf);
		luaL_error(L, "%s: %s", path, invalid);
	}
	set->buf = buf;
	return 1; /* object */
}

static const luaL_Reg luaset_lib[] = {
	{"new", luaset_new},
	{"load", luaset_load},
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

