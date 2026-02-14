/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Read-Copy-Update (RCU) synchronized hash table.
* This library provides a Lua-accessible hash table that uses RCU (Read-Copy-Update)
* for synchronization within the Linux kernel. RCU allows for very fast, lockless
* read operations, while write operations (updates and deletions) are synchronized
* to ensure data consistency. This makes it highly suitable for scenarios where
* read operations significantly outnumber write operations and high concurrency
* is required.
*
* Keys in the RCU table must be strings. Values must be Lunatik objects
* (i.e., userdata created by other Lunatik C modules like `data.new()`,
* `lunatik.runtime()`, etc.) or `nil` to delete an entry.
*
* A practical example of its usage can be found in `examples/shared.lua`,
* which implements an in-memory key-value store.
*
* @module rcu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/spinlock.h>
#include <linux/hashtable.h>
#include <linux/random.h>

#include <lunatik.h>

#include "luarcu.h"

#define LUARCU_MAXKEY	(LUAL_BUFFERSIZE)

typedef struct luarcu_entry_s {
	lunatik_object_t *object;
	struct hlist_node hlist;
	struct rcu_head rcu;
	char key[];
} luarcu_entry_t;

/***
* Represents an RCU-synchronized hash table.
* This is a userdata object returned by `rcu.table()`. It behaves like a
* standard Lua table for get (`__index`) and set (`__newindex`) operations
* but uses RCU internally for synchronization.
*
* Keys must be strings. Values stored must be Lunatik objects (e.g., created
* via `data.new()`, `lunatik.runtime()`) or `nil` (to remove an entry).
* When a Lunatik object is retrieved, it's a new reference to that object.
*
* @type rcu_table
* @usage
*  -- Assuming 'data' module is available for creating Lunatik objects
*  -- and 'rcu' module is required.
*  local rcu_store = rcu.table()
*  local my_data = data.new(10) -- Create a Lunatik object
*  my_data:setstring(0, "hello")
*
*  -- Set a value
*  rcu_store["my_key"] = my_data
*
*  -- Get a value
*  local retrieved_data = rcu_store["my_key"]
*  if retrieved_data then
*    print(retrieved_data:getstring(0)) -- Output: hello
*  end
*
*  -- Remove a value
*  rcu_store["my_key"] = nil
*
*  -- Iterate
*  rcu_store:map(function(k, v_obj)
*    print("Found key:", k, "Value object:", v_obj)
*  end)
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

#define luarcu_checkoptnil(L, i, checkopt, ...) \
	(lua_type((L), (i)) == LUA_TNIL ? NULL : checkopt((L), (i), ## __VA_ARGS__))

static int luarcu_table(lua_State *L);

static inline luarcu_entry_t *luarcu_lookup(luarcu_table_t *table, unsigned int index,
	const char *key, size_t keylen)
{
	luarcu_entry_t *entry;

	hlist_for_each_entry_rcu(entry, table->hlist + index, hlist)
		if (strncmp(entry->key, key, keylen) == 0)
			return entry;
	return NULL;
}

static luarcu_entry_t *luarcu_newentry(const char *key, size_t keylen, lunatik_object_t *object)
{
	luarcu_entry_t *entry;

	if (keylen >= LUARCU_MAXKEY || (entry = kmalloc(struct_size(entry, key, keylen + 1), GFP_ATOMIC)) == NULL)
		return NULL;

	strncpy(entry->key, key, keylen);
	entry->key[keylen] = '\0';
	entry->object = object;
	lunatik_getobject(object);
	return entry;
}

static inline void luarcu_free(luarcu_entry_t *entry)
{
	lunatik_putobject(entry->object);
	kfree_rcu(entry, rcu);
}

LUNATIK_OBJECTCHECKER(luarcu_checktable, luarcu_table_t *);

static int luarcu_cloneobject(lua_State *L)
{
	lunatik_object_t *object = (lunatik_object_t *)lua_touserdata(L, 1);
	lunatik_cloneobject(L, object);
	return 1;
}

lunatik_object_t *luarcu_gettable(lunatik_object_t *table, const char *key, size_t keylen)
{
	luarcu_table_t *_table = (luarcu_table_t *)table->private;
	unsigned int index = luarcu_hash(_table, key, keylen);
	lunatik_object_t *value = NULL;
	luarcu_entry_t *entry;

	rcu_read_lock();
	entry = luarcu_lookup(_table, index, key, keylen);
	if (entry != NULL) {
		/* entry might be released after rcu_read_unlock */
		value = entry->object; /* thus we need to store object pointer */
		lunatik_getobject(value);
	}
	rcu_read_unlock();
	return value;
}
EXPORT_SYMBOL(luarcu_gettable);

int luarcu_settable(lunatik_object_t *table, const char *key, size_t keylen, lunatik_object_t *object)
{
	int ret = 0;
	luarcu_table_t *tab = (luarcu_table_t *)table->private;
	luarcu_entry_t *old;
	unsigned int index = luarcu_hash(tab, key, keylen);

	lunatik_lock(table);
	rcu_read_lock();
	old = luarcu_lookup(tab, index, key, keylen);
	rcu_read_unlock();
	if (object) {
		luarcu_entry_t *new = luarcu_newentry(key, keylen, object);
		if (new == NULL) {
			ret = -ENOMEM;
			goto unlock;
		}

		if (!old)
			hlist_add_head_rcu(&new->hlist, tab->hlist + index);
		else {
			hlist_replace_rcu(&old->hlist, &new->hlist);
			luarcu_free(old);
		}
	}
	else if (old) {
		hlist_del_rcu(&old->hlist);
		luarcu_free(old);
	}
unlock:
	lunatik_unlock(table);
	return ret;
}
EXPORT_SYMBOL(luarcu_settable);

/***
* Retrieves a value (a Lunatik object) from the RCU table.
* This is the Lua `__index` metamethod, allowing table-like access `rcu_table[key]`.
* Read operations are RCU-protected and lockless.
* @function __index
* @tparam rcu_table self The RCU table instance.
* @tparam string key The key to look up in the table.
* @treturn lunatik_object The Lunatik object associated with the key, or `nil` if the key is not found.
*   A new reference to the object is returned.
* @usage
*  local my_object = my_rcu_table["some_key"]
*  if my_object then
*    -- Use my_object
*  end
*/
static int luarcu_index(lua_State *L)
{
	lunatik_object_t *table = lunatik_checkobject(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_object_t *value = luarcu_gettable(table, key, keylen);

	if (value == NULL)
		lua_pushnil(L);
	else {
		lua_pushcfunction(L, luarcu_cloneobject);
		lua_pushlightuserdata(L, value);
		if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
			lunatik_putobject(value);
			lua_error(L);
		}
	}
	return 1; /* value */
}

/***
* Sets or removes a value in the RCU table.
* This is the Lua `__newindex` metamethod, allowing table-like assignment `rcu_table[key] = value`.
* Write operations are synchronized.
* @function __newindex
* @tparam rcu_table self The RCU table instance.
* @tparam string key The key to set or update.
* @tparam lunatik_object|nil value The Lunatik object to associate with the key.
*   If `nil`, the key-value pair is removed from the table.
* @raise Error if memory allocation fails during new entry creation.
* @usage
*   local data_obj = data.new(5) -- Assuming 'data' module
*   my_rcu_table["new_key"] = some_lunatik_object
*   my_rcu_table["another_key"] = nil -- Removes 'another_key'
*/
static int luarcu_newindex(lua_State *L)
{
	lunatik_object_t *table = lunatik_checkobject(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_object_t *object = luarcu_checkoptnil(L, 3, lunatik_checkobject);

	if (luarcu_settable(table, key, keylen, object) < 0)
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

static int luarcu_map_handle(lua_State *L)
{
	const char *key = (const char *)lua_touserdata(L, 2);
	lunatik_object_t *value = (lunatik_object_t *)lua_touserdata(L, 3);

	BUG_ON(!key || !value);

	lua_pop(L, 2); /* key, value */

	lua_pushstring(L, key);
	lunatik_pushobject(L, value);
	lua_call(L, 2, 0);

	return 0;
}

static inline int luarcu_map_call(lua_State *L, int cb, const char *key, lunatik_object_t *value)
{
	lua_pushcfunction(L, luarcu_map_handle);
	lua_pushvalue(L, cb);
	lua_pushlightuserdata(L, (void *)key);
	lua_pushlightuserdata(L, value);

	return lua_pcall(L, 3, 0, 0); /* handle(cb, key, value) */
}

/***
* Iterates over the RCU table and calls a callback for each key-value pair.
* The iteration is RCU-protected. The order of iteration is not guaranteed.
* For each entry, a new reference to the value (Lunatik object) is obtained
* before calling the callback and released after the callback returns.
*
* @function map
* @tparam rcu_table self The RCU table instance.
* @tparam function callback A Lua function that will be called for each entry in the table.
*   The callback receives two arguments:
*
*   1. `key` (string): The key of the current entry.
*   2. `value` (lunatik_object): The Lunatik object associated with the key.
*
* @treturn nil
* @raise Error if the callback function raises an error during its execution.
* @usage
*   -- Example: Iterating and printing content if values are 'data' objects
*   my_rcu_table:map(function(k, v_obj)
*     -- v_obj is the Lunatik object stored for the key.
*     -- If it's a 'data' object (a common use case, see examples/shared.lua):
*     print("Key:", k, "Content from data object:", v_obj:getstring(0))
*   end)
*/
static int luarcu_map(lua_State *L)
{
	luarcu_table_t *table = luarcu_checktable(L, 1);
	unsigned int bucket;
	luarcu_entry_t *n, *entry;

	luaL_checktype(L, 2, LUA_TFUNCTION); /* cb */
	lua_remove(L, 1); /* table */

	rcu_read_lock();
	luarcu_foreach(table, bucket, n, entry) {
		char key[LUARCU_MAXKEY];

		strncpy(key, entry->key, LUARCU_MAXKEY);
		key[LUARCU_MAXKEY - 1] = '\0';
		lunatik_object_t *value = entry->object;
		lunatik_getobject(value);

		rcu_read_unlock();
		int ret = luarcu_map_call(L, 1, key, value);
		lunatik_putobject(value);
		if (ret != LUA_OK)
			lua_error(L);
		rcu_read_lock();
	}
	rcu_read_unlock();
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

static const lunatik_class_t luarcu_class = {
	.name = "rcu",
	.methods = luarcu_mt,
	.release = luarcu_release,
};

lunatik_object_t *luarcu_newtable(size_t size, bool sleep)
{
	lunatik_object_t *object;

	size = roundup_pow_of_two(size);
	if ((object = lunatik_createobject(&luarcu_class, luarcu_sizeoftable(size), sleep))!= NULL)
		luarcu_inittable((luarcu_table_t *)object->private, size);
	return object;
}
EXPORT_SYMBOL(luarcu_newtable);

/***
* Creates a new RCU-synchronized hash table.
* @function table
* @tparam[opt=1024] integer size Specifies the initial number of hash buckets (internal slots) for the table.
*   This is **not** a hard limit on the number of entries the table can store.
*   The provided `size` will be rounded up to the nearest power of two.
*   Choosing an appropriate `size` involves a trade-off between memory usage and performance:
*
*   - more buckets (larger `size`): Consumes more memory for the table structure itself,
*     even if many buckets remain empty. However, it reduces the probability of hash collisions,
*     which can significantly speed up operations (lookups, insertions, deletions),
*     especially when storing a large number of entries.
*   - fewer buckets (smaller `size`): Uses less memory for the table's internal array.
*     However, if the number of entries is high relative to the number of buckets,
*     it increases the chance of hash collisions. This means more entries might end up
*     in the same bucket, forming longer linked lists that need to be traversed,
*     thereby slowing down operations.
*
*   **Guidance**: For optimal performance, aim for a `size` that is roughly in the order of,
*   or somewhat larger than, the maximum number of entries you anticipate storing. This helps
*   maintain a low average number of entries per bucket (a low "load factor," ideally close to 1).
*   The table can hold more entries than its `size` (number of buckets), but performance
*   will degrade as the load factor increases. The default is a general-purpose starting point
*   suitable for many common use cases.
* @treturn rcu_table A new RCU table object, or raises an error if memory allocation fails.
* @usage
*   local my_rcu_table = rcu.table() -- Default: 1024 buckets, good for moderate entries.
*   local small_table = rcu.table(128) -- 128 buckets, for fewer expected entries.
*   local large_table = rcu.table(8192) -- 8192 buckets, for many expected entries.
* @within rcu
*/
static int luarcu_table(lua_State *L)
{
	size_t size = roundup_pow_of_two(luaL_optinteger(L, 1, LUARCU_DEFAULT_SIZE));
	lunatik_object_t *object = lunatik_newobject(L, &luarcu_class, luarcu_sizeoftable(size));

	luarcu_inittable((luarcu_table_t *)object->private, size);
	return 1; /* object */
}

LUNATIK_NEWLIB(rcu, luarcu_lib, &luarcu_class, NULL);

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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

