/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* RCU-synchronized hash table.
* Provides a concurrent hash table using Read-Copy-Update (RCU) synchronization.
* Reads are lockless; writes are serialized. Keys are strings, values can be
* booleans, integers, lunatik objects, or `nil` (to delete an entry).
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

#define LUARCU_MAXKEY	(LUAL_BUFFERSIZE)

typedef struct luarcu_entry_s {
	lunatik_value_t value;
	struct hlist_node hlist;
	struct rcu_head rcu;
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
		if (strncmp(entry->key, key, keylen) == 0)
			return entry;
	return NULL;
}

static luarcu_entry_t *luarcu_newentry(const char *key, size_t keylen, lunatik_value_t *value)
{
	luarcu_entry_t *entry;

	if (keylen >= LUARCU_MAXKEY || (entry = kmalloc(struct_size(entry, key, keylen + 1), GFP_ATOMIC)) == NULL)
		return NULL;

	strncpy(entry->key, key, keylen);
	entry->key[keylen] = '\0';
	entry->value = *value;
	if (lunatik_isuserdata(value))
		lunatik_getobject(value->object);
	else if (lunatik_isstring(value))
		lunatik_getstring(value->string);
	return entry;
}

static inline void luarcu_free(luarcu_entry_t *entry)
{
	if (lunatik_isuserdata(&entry->value))
		lunatik_putobject(entry->value.object);
	else if (lunatik_isstring(&entry->value))
		lunatik_putstring(entry->value.string);
	kfree_rcu(entry, rcu);
}

LUNATIK_OBJECTCHECKER(luarcu_checktable, luarcu_table_t *);

void luarcu_getvalue(lunatik_object_t *table, const char *key, size_t keylen, lunatik_value_t *value)
{
	luarcu_table_t *_table = (luarcu_table_t *)table->private;
	unsigned int index = luarcu_hash(_table, key, keylen);
	luarcu_entry_t *entry;

	rcu_read_lock();
	if ((entry = luarcu_lookup(_table, index, key, keylen)) == NULL)
		value->type = LUA_TNIL;
	else {
		*value = entry->value;
		if (lunatik_isuserdata(value))
			lunatik_getobject(value->object);
		else if (lunatik_isstring(value))
			lunatik_getstring(value->string);
	}
	rcu_read_unlock();
}
EXPORT_SYMBOL(luarcu_getvalue);

int luarcu_setvalue(lunatik_object_t *table, const char *key, size_t keylen, lunatik_value_t *value)
{
	int ret = 0;
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
EXPORT_SYMBOL(luarcu_setvalue);

/***
* Retrieves a value from the table (RCU-protected, lockless).
* @function __index
* @tparam string key
* @treturn boolean|integer|object|nil
*/
static int luarcu_index(lua_State *L)
{
	lunatik_object_t *table = lunatik_checkobject(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_value_t value;

	luarcu_getvalue(table, key, keylen, &value);
	lunatik_pushvalue(L, &value);
	lunatik_putvalue(&value);
	return 1; /* value */
}

/***
* Sets or removes a value in the table (serialized).
* Assigning `nil` removes the entry.
* @function __newindex
* @tparam string key
* @tparam boolean|integer|object|nil value
* @raise Error on memory allocation failure.
*/
static int luarcu_newindex(lua_State *L)
{
	lunatik_object_t *table = lunatik_checkobject(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);

	lunatik_value_t value;
	lunatik_checkvalue(L, 3, &value);
	int ret = luarcu_setvalue(table, key, keylen, &value);
	lunatik_putvalue(&value);
	if (ret < 0)
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
	lunatik_value_t *value = (lunatik_value_t *)lua_touserdata(L, 3);

	BUG_ON(!key || !value);

	lua_pop(L, 2); /* key, value */

	lua_pushstring(L, key);
	if (lunatik_isuserdata(value))
		lunatik_pushobject(L, value->object);
	else
		lunatik_pushvalue(L, value);
	lua_call(L, 2, 0);

	return 0;
}

static inline int luarcu_map_call(lua_State *L, int cb, const char *key, lunatik_value_t *value)
{
	lua_pushcfunction(L, luarcu_map_handle);
	lua_pushvalue(L, cb);
	lua_pushlightuserdata(L, (void *)key);
	lua_pushlightuserdata(L, value);

	return lua_pcall(L, 3, 0, 0); /* handle(cb, key, value) */
}

/***
* Iterates over the table calling `callback(key, value)` for each entry.
* Iteration is RCU-protected; order is not guaranteed.
* @function map
* @tparam function callback `function(key, value)`.
* @raise Error if callback raises.
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
		lunatik_value_t value = entry->value;

		strncpy(key, entry->key, LUARCU_MAXKEY);
		key[LUARCU_MAXKEY - 1] = '\0';

		if (lunatik_isuserdata(&value))
			lunatik_getobject(value.object);
		else if (lunatik_isstring(&value))
			lunatik_getstring(value.string);

		rcu_read_unlock();
		int ret = luarcu_map_call(L, 1, key, &value);
		if (lunatik_isuserdata(&value))
			lunatik_putobject(value.object);
		else if (lunatik_isstring(&value))
			lunatik_putstring(value.string);
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
	.opt = LUNATIK_OPT_SOFTIRQ,
};

lunatik_object_t *luarcu_newtable(size_t size, lunatik_opt_t opt)
{
	lunatik_object_t *object;

	size = roundup_pow_of_two(size);
	if ((object = lunatik_createobject(&luarcu_class, luarcu_sizeoftable(size), opt)) != NULL)
		luarcu_inittable((luarcu_table_t *)object->private, size);
	return object;
}
EXPORT_SYMBOL(luarcu_newtable);

/***
* Creates a new RCU hash table.
* @function table
* @tparam[opt=256] integer size Number of hash buckets (rounded up to power of two).
* @treturn rcu_table
* @usage
*   local t = rcu.table()      -- 256 buckets (default)
*   local t = rcu.table(8192)  -- 8192 buckets
* @within rcu
*/
static int luarcu_table(lua_State *L)
{
	size_t size = roundup_pow_of_two(luaL_optinteger(L, 1, LUARCU_DEFAULT_SIZE));
	lunatik_object_t *object = lunatik_newobject(L, &luarcu_class, luarcu_sizeoftable(size), LUNATIK_OPT_NONE);

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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

