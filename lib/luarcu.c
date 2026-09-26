/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* RCU-synchronized hash table.
* Provides a concurrent hash table using Read-Copy-Update (RCU) synchronization.
* Reads are lockless; writes are serialized. Keys are strings, values can be
* booleans, integers, lunatik objects, or `nil` (to delete an entry). A read that
* meets a writer releasing the entry's object sees the entry gone.
*
* See `examples/shared.lua` for a practical example.
* @module rcu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/spinlock.h>
#include <linux/hashtable.h>
#include <linux/random.h>

#include <lunatik.h>

#include "luarcu.h"

typedef struct luarcu_entry_s {
	lunatik_value_t value;
	struct hlist_node hlist;
	struct rcu_head rcu;
	size_t keylen;
	char key[];
} luarcu_entry_t;

/***
* RCU hash table object.
* Supports table-like access via `__index` and `__newindex`.
* @type rcu_table
* @usage
*  local t = rcu.table()
*  t["key"] = true        -- boolean
*  t["n"]   = 42          -- integer
*  t["obj"] = data.new(8) -- object
*  print(t["key"])        -- true
*  t["key"] = nil         -- delete
*/

typedef struct luarcu_table_s {
	size_t size;
	unsigned int seed;
	struct hlist_head hlist[];
} luarcu_table_t;

#define luarcu_sizeoftable(size)	(sizeof(luarcu_table_t) + sizeof(struct hlist_head) * (size))

/* size is always a power of 2; thus `size - 1` turns on every valid bit */
#define luarcu_mask(table)			((table)->size - 1)
#define luarcu_hash(table, key, keylen)		(lunatik_hash((key), (keylen), (table)->seed) & luarcu_mask(table))
#define luarcu_seed()				get_random_u32()

#define luarcu_entry(ptr, pos)		hlist_entry_safe(rcu_dereference_raw(ptr), typeof(*(pos)), hlist)
#define luarcu_foreach(table, bucket, n, pos)							\
	for (bucket = 0, pos = NULL; pos == NULL && bucket < (table)->size; bucket++)		\
		for (pos = luarcu_entry(hlist_first_rcu(&(table)->hlist[bucket]), pos);		\
			pos && ({ n = luarcu_entry(hlist_next_rcu(&(pos)->hlist), pos); 1; });	\
			pos = n)

static int luarcu_table(lua_State *L);

static inline luarcu_entry_t *luarcu_lookup(luarcu_table_t *table, unsigned int index,
	const char *key, size_t keylen)
{
	luarcu_entry_t *entry;

	hlist_for_each_entry_rcu(entry, table->hlist + index, hlist)
		if (entry->keylen == keylen && memcmp(entry->key, key, keylen) == 0)
			return entry;
	return NULL;
}

static luarcu_entry_t *luarcu_newentry(const char *key, size_t keylen, lunatik_value_t *value)
{
	luarcu_entry_t *entry;

	if (keylen >= LUARCU_MAXKEY || (entry = kmalloc(struct_size(entry, key, keylen), GFP_ATOMIC)) == NULL)
		return NULL;

	memcpy(entry->key, key, keylen);
	entry->keylen = keylen;
	entry->value = *value;
	if (lunatik_isuserdata(value))
		lunatik_getobject(value->object);
	return entry;
}

static inline void luarcu_free(luarcu_entry_t *entry)
{
	if (lunatik_isuserdata(&entry->value))
		lunatik_putobject(entry->value.object);
	kfree_rcu(entry, rcu);
}

static const lunatik_class_t luarcu_class;

LUNATIK_PRIVATECHECKER(luarcu_checktable, luarcu_table_t *, &luarcu_class);

static inline void luarcu_findvalue(luarcu_table_t *table, const char *key, size_t keylen, lunatik_value_t *value)
{
	unsigned int index = luarcu_hash(table, key, keylen);
	luarcu_entry_t *entry;

	rcu_read_lock();
	if ((entry = luarcu_lookup(table, index, key, keylen)) == NULL)
		value->type = LUA_TNIL;
	else {
		*value = entry->value;
		if (lunatik_isuserdata(value) && !lunatik_getobject_rcu(value->object))
			value->type = LUA_TNIL;
	}
	rcu_read_unlock();
}

void luarcu_getvalue(lunatik_object_t *table, const char *key, size_t keylen, lunatik_value_t *value)
{
	luarcu_findvalue((luarcu_table_t *)table->private, key, keylen, value);
}
EXPORT_SYMBOL(luarcu_getvalue);

int luarcu_setvalue(lunatik_object_t *table, const char *key, size_t keylen, lunatik_value_t *value)
{
	luarcu_table_t *tab = (luarcu_table_t *)table->private;
	luarcu_entry_t *old;
	unsigned int index = luarcu_hash(tab, key, keylen);

	lunatik_lock(table);
	rcu_read_lock();
	old = luarcu_lookup(tab, index, key, keylen);
	rcu_read_unlock();
	if (value->type != LUA_TNIL) {
		luarcu_entry_t *new = luarcu_newentry(key, keylen, value);
		if (new == NULL) {
			lunatik_unlock(table);
			return -ENOMEM;
		}

		if (!old)
			hlist_add_head_rcu(&new->hlist, tab->hlist + index);
		else
			hlist_replace_rcu(&old->hlist, &new->hlist);
	}
	else if (old)
		hlist_del_rcu(&old->hlist);
	lunatik_unlock(table);

	if (old != NULL)
		luarcu_free(old); /* the value's put may close a runtime or a socket, which sleeps */
	return 0;
}
EXPORT_SYMBOL(luarcu_setvalue);

/***
* Retrieves a value from the table (RCU-protected, lockless).
* @function __index
* @tparam string key
* @treturn boolean|integer|object|nil `nil` for a key without an entry, and for one whose
*   object a writer is releasing
*/
static int luarcu_index(lua_State *L)
{
	lunatik_object_t *table = lunatik_checkobjectclass(L, 1, &luarcu_class);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_value_t value;

	luarcu_getvalue(table, key, keylen, &value);
	lunatik_pushvalue(L, &value);
	return 1; /* value */
}

/***
* Sets or removes a value in the table (serialized).
* Assigning `nil` removes the entry. The value an assignment replaces or removes is
* released on the assigning task once the table's lock is dropped, so a runtime or a
* socket whose last reference the entry held closes there, in the writer's own context:
* in softirq when a softirq runtime writes the table, with IRQs off when a hardirq one does.
* @function __newindex
* @tparam string key up to `LUARCU_MAXKEY` bytes, exclusive
* @tparam boolean|integer|object|nil value
* @raise Error if the key is out of bounds, or on memory allocation failure.
*/
static int luarcu_newindex(lua_State *L)
{
	lunatik_object_t *table = lunatik_checkobjectclass(L, 1, &luarcu_class);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_checkbounds(L, 2, keylen, 0, LUARCU_MAXKEY - 1);

	lunatik_value_t value;
	lunatik_checkvalue(L, 3, &value);
	if (luarcu_setvalue(table, key, keylen, &value) < 0)
		luaL_error(L, "not enough memory");
	return 0;
}

static void luarcu_release(void *private)
{
	luarcu_table_t *table = (luarcu_table_t *)private;
	unsigned int bucket;
	luarcu_entry_t *n, *entry;

	luarcu_foreach(table, bucket, n, entry) {
		hlist_del_rcu(&entry->hlist);
		luarcu_free(entry);
	}
}

static inline void luarcu_inittable(luarcu_table_t *table, size_t size)
{
	__hash_init(table->hlist, size);
	table->size = size;
	table->seed = luarcu_seed();
}

/* a key in the walk's buffer: its length, which LUARCU_MAXKEY keeps within a byte, then its bytes */
typedef u8 luarcu_keylen_t;
static_assert(LUARCU_MAXKEY - 1 <= U8_MAX);

static inline void luarcu_pack(char *dst, const char *key, luarcu_keylen_t keylen)
{
	memcpy(dst, &keylen, sizeof(keylen));
	memcpy(dst + sizeof(keylen), key, keylen);
}

static inline const char *luarcu_unpack(const char *src, luarcu_keylen_t *keylen)
{
	memcpy(keylen, src, sizeof(*keylen));
	return src + sizeof(*keylen);
}

/* noinline keeps the symbol in kallsyms, where tests/rcu/map_next reads whether the module carries the walk */
static noinline size_t luarcu_copykeys(luarcu_table_t *table, unsigned int bucket, char *keys, size_t size)
{
	luarcu_entry_t *entry;
	size_t need = 0;

	rcu_read_lock();
	hlist_for_each_entry_rcu(entry, table->hlist + bucket, hlist) {
		size_t len = sizeof(luarcu_keylen_t) + entry->keylen;

		if (need + len <= size)
			luarcu_pack(keys + need, entry->key, entry->keylen);
		need += len;
	}
	rcu_read_unlock();
	return need;
}

static size_t luarcu_readkeys(lua_State *L, int ix, luarcu_table_t *table, unsigned int bucket)
{
	char *keys = (char *)lua_touserdata(L, ix);
	size_t size = lua_rawlen(L, ix);
	size_t need = luarcu_copykeys(table, bucket, keys, size);

	while (need > size) { /* a writer may have added to the bucket since the read */
		keys = (char *)lua_newuserdatauv(L, need, 0);
		lua_replace(L, ix);
		size = need;
		need = luarcu_copykeys(table, bucket, keys, size);
	}
	return need;
}

static inline void luarcu_map_call(lua_State *L, int cb, luarcu_table_t *table, const char *key, size_t keylen)
{
	lunatik_value_t value;

	lua_pushvalue(L, cb);
	lua_pushlstring(L, key, keylen); /* before the lookup, so its raise holds no reference */
	luarcu_findvalue(table, key, keylen, &value);
	if (value.type == LUA_TNIL)
		lua_pop(L, 2); /* cb, key */
	else {
		lunatik_pushvalue(L, &value);
		lua_call(L, 2, 0); /* cb(key, value) */
	}
}

enum luarcu_map_slots { LUARCU_MAP_TABLE = 1, LUARCU_MAP_CB, LUARCU_MAP_KEYS };

/***
* Iterates over the table calling `callback(key, value)` for each entry.
* Iteration is RCU-protected; order is not guaranteed. The walk reads a bucket's keys once and
* looks each one up before its call: an entry the callback removes is not visited, one it
* replaces is visited with its new value, and one it adds is visited only if its bucket is
* still ahead.
* @function map
* @tparam function callback `function(key, value)`; an entry whose object a writer is
*   releasing is skipped.
* @raise Error if callback raises, or if the keys of a bucket cannot be allocated.
*/
static int luarcu_map(lua_State *L)
{
	luarcu_table_t *table = luarcu_checktable(L, LUARCU_MAP_TABLE);
	unsigned int bucket;

	luaL_checktype(L, LUARCU_MAP_CB, LUA_TFUNCTION);
	lua_settop(L, LUARCU_MAP_CB);
	lua_newuserdatauv(L, 0, 0); /* LUARCU_MAP_KEYS */

	for (bucket = 0; bucket < table->size; bucket++) {
		size_t used = luarcu_readkeys(L, LUARCU_MAP_KEYS, table, bucket);
		const char *keys = (const char *)lua_touserdata(L, LUARCU_MAP_KEYS);
		const char *end = keys + used;

		while (keys < end) {
			luarcu_keylen_t keylen;
			const char *key = luarcu_unpack(keys, &keylen);

			luarcu_map_call(L, LUARCU_MAP_CB, table, key, keylen);
			keys = key + keylen;
		}
	}
	return 0;
}

static const struct luaL_Reg luarcu_lib[] = {
	{"table", luarcu_table},
	{"map", luarcu_map},
	{NULL, NULL}
};

static const struct luaL_Reg luarcu_mt[] = {
	{"__newindex", luarcu_newindex},
	{"__index", luarcu_index},
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};

LUNATIK_OPENER(rcu);
static const lunatik_class_t luarcu_class = {
	.name = "rcu.table",
	.methods = luarcu_mt,
	.release = luarcu_release,
	.opener = luaopen_rcu,
	.opt = LUNATIK_OPT_SOFTIRQ,
};

lunatik_object_t *luarcu_newtable(size_t size, lunatik_opt_t opt)
{
	lunatik_object_t *object;

	size = roundup_pow_of_two(clamp_t(size_t, size, 1, LUARCU_MAXSIZE));
	if ((object = lunatik_createobject(&luarcu_class, luarcu_sizeoftable(size), opt)) != NULL)
		luarcu_inittable((luarcu_table_t *)object->private, size);
	return object;
}
EXPORT_SYMBOL(luarcu_newtable);

/***
* Creates a new RCU hash table.
* @function table
* @tparam[opt=256] integer size Number of hash buckets (rounded up to power of two), from 1 up to
*   `LUARCU_MAXSIZE`, the largest count whose table can be sized; what memory serves is the allocator's.
* @treturn rcu_table
* @raise if out of bounds or the allocation fails
* @usage
*   local t = rcu.table()      -- 256 buckets (default)
*   local t = rcu.table(8192)  -- 8192 buckets
* @within rcu
*/
static int luarcu_table(lua_State *L)
{
	lua_Integer buckets = luaL_optinteger(L, 1, LUARCU_DEFAULT_SIZE);
	lunatik_checkbounds(L, 1, buckets, 1, LUARCU_MAXSIZE);
	size_t size = roundup_pow_of_two(buckets);
	lunatik_object_t *object = lunatik_newobject(L, &luarcu_class, luarcu_sizeoftable(size), LUNATIK_OPT_NONE);

	luarcu_inittable((luarcu_table_t *)object->private, size);
	return 1; /* object */
}

LUNATIK_CLASSES(rcu, &luarcu_class);
LUNATIK_NEWLIB(rcu, luarcu_lib, luarcu_classes);

static int __init luarcu_init(void)
{
	return 0;
}

static void __exit luarcu_exit(void)
{
}

module_init(luarcu_init);
module_exit(luarcu_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

