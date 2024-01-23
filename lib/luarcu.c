/*
* Copyright (c) 2023 ring-0 Ltda.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/spinlock.h>
#include <linux/hashtable.h>
#include <linux/hashtable.h>
#include <linux/random.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

#define LUARCU_DEFAULT_SIZE	(256)

typedef struct luarcu_entry_s {
	const char *key;
	lunatik_object_t *object;
	struct hlist_node hlist;
	struct rcu_head rcu;
} luarcu_entry_t;

typedef struct luarcu_table_s {
	size_t size;
	unsigned int seed;
	struct hlist_head hlist[];
} luarcu_table_t;

#define luarcu_sizeoftable(size)	(sizeof(luarcu_table_t) + sizeof(struct hlist_head) * (size))

#include <lua/lstring.h>
/* size is always a power of 2; thus `size - 1` turns on every valid bit */
#define luarcu_mask(table)			((table)->size - 1)
#define luarcu_hash(table, key, keylen)		(luaS_hash((key), (keylen), (table)->seed) & luarcu_mask(table))
#define luarcu_seed()				get_random_u32()

#define luarcu_foreach(table, bucket, entry)							\
	for (bucket = 0, entry = NULL; entry == NULL && bucket < (table)->size; bucket++)	\
		hlist_for_each_entry_rcu(entry, &(table)->hlist[bucket], hlist)

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

static luarcu_entry_t *luarcu_newentry(const char *key, lunatik_object_t *object)
{
	luarcu_entry_t *entry = (luarcu_entry_t *)kmalloc(sizeof(luarcu_entry_t), GFP_ATOMIC);
	if (entry == NULL)
		return NULL;

	entry->key = key;
	entry->object = object;
	lunatik_getobject(object);
	return entry;
}

static inline void luarcu_free(luarcu_entry_t *entry)
{
	lunatik_putobject(entry->object);
	kfree(entry);
}

static int luarcu_replace(luarcu_entry_t *old, lunatik_object_t *object)
{
	luarcu_entry_t *new = luarcu_newentry(old->key, object);
	if (new == NULL)
		return -1;

	hlist_replace_rcu(&old->hlist, &new->hlist);
	luarcu_free(old);
	return 0;
}

static int luarcu_add(luarcu_table_t *table, unsigned int index, const char *key, size_t keylen, lunatik_object_t *object)
{
	char *entry_key;
	luarcu_entry_t *entry;

	keylen++; /* null-terminated */
	entry_key = (char *)kmalloc(sizeof(const char) * keylen, GFP_ATOMIC);
	if (entry_key == NULL)
		return -1;

	entry = luarcu_newentry(entry_key, object);
	if (entry == NULL) {
		kfree(entry_key);
		return -1;
	}

	strncpy(entry_key, key, keylen);
	hlist_add_head_rcu(&entry->hlist, table->hlist + index);
	return 0;
}

static inline void luarcu_remove(luarcu_entry_t *entry)
{
	hlist_del_rcu(&entry->hlist);
	kfree(entry->key);
	luarcu_free(entry);
}

static int luarcu_insert(luarcu_table_t *table, const char *key, size_t keylen, lunatik_object_t *object)
{
	luarcu_entry_t *entry;
	unsigned int index = luarcu_hash(table, key, keylen);
	int ret = 0;

	entry = luarcu_lookup(table, index, key, keylen);
	if (object)
		ret = entry ? luarcu_replace(entry, object) :
			luarcu_add(table, index, key, keylen, object);
	else if (entry)
		luarcu_remove(entry);

	return ret;
}

LUNATIK_OBJECTCHECKER(luarcu_checktable, luarcu_table_t *);

static int luarcu_cloneobject(lua_State *L)
{
	lunatik_object_t *object = (lunatik_object_t *)lua_touserdata(L, 1);
	lunatik_cloneobject(L, object);
	return 1;
}

static int luarcu_index(lua_State *L)
{
	luarcu_table_t *table = luarcu_checktable(L, 1);
	luarcu_entry_t *entry;
	lunatik_object_t *object;
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	unsigned int index = luarcu_hash(table, key, keylen);

	rcu_read_lock();
	entry = luarcu_lookup(table, index, key, keylen);
	if (entry == NULL) {
		rcu_read_unlock();
		lua_pushnil(L);
		return 1;
	}

	/* entry might be released after rcu_read_unlock */
	object = entry->object; /* thus we need to store object pointer */
	lunatik_getobject(object);
	rcu_read_unlock();

	lua_pushcfunction(L, luarcu_cloneobject);
	lua_pushlightuserdata(L, object);
	if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
		lunatik_putobject(object);
		lua_error(L);
	}
	return 1; /* object */
}

static int luarcu_newindex(lua_State *L)
{
	lunatik_object_t *table = lunatik_checkobject(L, 1);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_object_t *object = luarcu_checkoptnil(L, 3, lunatik_checkobject);
	int ret;

	lunatik_lock(table);
	ret = luarcu_insert(table->private, key, keylen, object);
	lunatik_unlock(table);
	if (!rcu_read_lock_held())
		synchronize_rcu();

	if (ret != 0)
		luaL_error(L, "not enough memory");
	return 0;
}

static void luarcu_release(void *private)
{
	luarcu_table_t *table = (luarcu_table_t *)private;
	unsigned int bucket;
	luarcu_entry_t *entry;

	luarcu_foreach(table, bucket, entry)
		luarcu_remove(entry);
}

static const struct luaL_Reg luarcu_lib[] = {
	{"table", luarcu_table},
	{NULL, NULL}
};

static const struct luaL_Reg luarcu_mt[] = {
	{"__newindex", luarcu_newindex},
	{"__index", luarcu_index},
	{"__gc", lunatik_deleteobject},
	{NULL, NULL}
};

static const lunatik_class_t luarcu_class = {
	.name = "rcu.table",
	.methods = luarcu_mt,
	.release = luarcu_release,
};

static int luarcu_table(lua_State *L)
{
	size_t size = roundup_pow_of_two(luaL_optinteger(L, 1, LUARCU_DEFAULT_SIZE));
	lunatik_object_t *object = lunatik_newobject(L, &luarcu_class, luarcu_sizeoftable(size));
	luarcu_table_t *table = object->private;

	__hash_init(table->hlist, size);
	table->size = size;
	table->seed = luarcu_seed();
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

