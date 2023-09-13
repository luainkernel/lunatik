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
#include <linux/kref.h>

#include <lua.h>
#include <lauxlib.h>

#include <lunatik.h>

#define LUARCU_MT		"rcu.table"
#define LUARCU_DEFAULT_SIZE	(256)

typedef struct luarcu_entry_s {
	const char *key;
	const void *data;
	size_t len;
	struct hlist_node hlist;
	struct rcu_head rcu;
} luarcu_entry_t;

typedef struct luarcu_table_s {
	size_t size;
	unsigned int seed;
	spinlock_t lock;
	struct kref kref;
	struct hlist_head hlist[];
} luarcu_table_t;

static luarcu_table_t *luarcu_registry;

#define luarcu_newptable(L)		((luarcu_table_t **)lua_newuserdatauv((L), sizeof(luarcu_table_t *), 0))
#define luarcu_checkptable(L, i)	((luarcu_table_t **)luaL_checkudata((L), (i), LUARCU_MT))
#define luarcu_istable(entry)		((entry)->len == 0)
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

static inline void luarcu_remove(luarcu_entry_t *entry);

static void luarcu_release(struct kref *kref)
{
	luarcu_table_t *table = container_of(kref, luarcu_table_t, kref);
	unsigned int bucket;
	luarcu_entry_t *entry;

	luarcu_foreach(table, bucket, entry)
		luarcu_remove(entry);

	kfree(table);
}

#define luarcu_ref(table)	(&((luarcu_table_t *)(table))->kref)
#define luarcu_refinit(table)	kref_init(luarcu_ref(table))
#define luarcu_refget(table)	kref_get(luarcu_ref(table))
#define luarcu_refput(table)	kref_put(luarcu_ref(table), luarcu_release)

static inline luarcu_table_t *luarcu_checktable(lua_State *L, int index)
{
	luarcu_table_t **ptable = luarcu_checkptable(L, index);
	luarcu_table_t *table = *ptable;

	if (table == NULL)
		luaL_error(L, "invalid rcu");
	return table;
}

static inline luarcu_entry_t *luarcu_lookup(luarcu_table_t *table, unsigned int index,
	const char *key, size_t keylen)
{
	luarcu_entry_t *entry;
    
	hlist_for_each_entry_rcu(entry, table->hlist + index, hlist)
		if (strncmp(entry->key, key, keylen) == 0)
			return entry;
	return NULL;
}

static luarcu_entry_t *luarcu_alloc(const char *key, const void *data, size_t len)
{
	luarcu_entry_t *entry = (luarcu_entry_t *)kmalloc(sizeof(luarcu_entry_t), GFP_ATOMIC);
	if (entry == NULL)
		return NULL;

	entry->len = len;
	entry->key = key;

	if (!luarcu_istable(entry)) {
		entry->data = kmalloc(len, GFP_ATOMIC);
		if (entry->data == NULL) {
			kfree(entry);
			return NULL;
		}
		memcpy((void *)entry->data, data, len);
	}
	else
		entry->data = data;

	return entry;
}

static inline void luarcu_free(luarcu_entry_t *entry)
{
	if (luarcu_istable(entry))
		luarcu_refput(entry->data);
	else
		kfree(entry->data);
	kfree(entry);
}

static int luarcu_replace(luarcu_entry_t *old, const void *data, size_t len)
{
	luarcu_entry_t *new = luarcu_alloc(old->key, data, len);
	if (new == NULL)
		return -1;

	hlist_replace_rcu(&old->hlist, &new->hlist);
	luarcu_free(old);
	return 0;
}

static int luarcu_add(luarcu_table_t *table, unsigned int index, const char *key, size_t keylen,
	const void *data, size_t len)
{
	char *entry_key;
	luarcu_entry_t *entry;

	keylen++; /* null-terminated */
	entry_key = (char *)kmalloc(sizeof(const char) * keylen, GFP_ATOMIC);
	if (entry_key == NULL)
		return -1;

	entry = luarcu_alloc(entry_key, data, len);
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

static void luarcu_insert(lua_State *L, luarcu_table_t *table, const char *key, size_t keylen,
	const void *data, size_t len)
{
	luarcu_entry_t *entry;
	unsigned int index = luarcu_hash(table, key, keylen);
	int ret = 0;

	spin_lock(&table->lock);

	entry = luarcu_lookup(table, index, key, keylen);
	if (data)
		ret = entry ? luarcu_replace(entry, data, len) :
			luarcu_add(table, index, key, keylen, data, len);
	else if (entry)
		luarcu_remove(entry);

	spin_unlock(&table->lock);
	if (!rcu_read_lock_held())
		synchronize_rcu();

	if (ret != 0)
		luaL_error(L, "failed to insert");
}

static int luarcu_index(lua_State *L)
{
	luarcu_table_t *table = luarcu_checktable(L, 1);
	luarcu_entry_t *entry;
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	unsigned int index = luarcu_hash(table, key, keylen);

	rcu_read_lock();
	entry = luarcu_lookup(table, index, key, keylen);
	if (entry == NULL) {
		lua_pushnil(L);
		goto out;
	}

	lua_pushlstring(L, entry->data, entry->len);
out:
	rcu_read_unlock();
	return 1;
}

static int luarcu_newindex(lua_State *L)
{
	luarcu_table_t *table = luarcu_checktable(L, 1);
	size_t len, keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	const char *data = luarcu_checkoptnil(L, 3, luaL_checklstring, &len);

	luarcu_insert(L, table, key, keylen, data, len);
	return 0;
}

static int luarcu_delete(lua_State *L)
{
	luarcu_table_t **ptable = luarcu_checkptable(L, 1);

	luarcu_refput(*ptable);
	*ptable = NULL;
	return 0;
}

static luarcu_table_t *luarcu_newtable(size_t size)
{
	luarcu_table_t *table = (luarcu_table_t *)kmalloc(luarcu_sizeoftable(size), GFP_ATOMIC);
	if (table != NULL) {
		luarcu_refinit(table);
		__hash_init(table->hlist, size);
		table->size = size;
		table->seed = luarcu_seed();
		spin_lock_init(&table->lock);
	}
	return table;
}

static int luarcu_table(lua_State *L)
{
	size_t size = roundup_pow_of_two(luaL_optinteger(L, 1, LUARCU_DEFAULT_SIZE));
	luarcu_table_t **ptable = luarcu_newptable(L);
	luarcu_table_t *table = luarcu_newtable(size);
	if (table == NULL)
		luaL_error(L, "failed to allocate table");
	*ptable = table;
	luaL_setmetatable(L, LUARCU_MT);
	return 1;
}

static int luarcu_publish(lua_State *L)
{
	size_t keylen;
	const char *key = luaL_checklstring(L, 1, &keylen);
	luarcu_table_t *table = luarcu_checkoptnil(L, 2, luarcu_checktable);

	luarcu_insert(L, luarcu_registry, key, keylen, table, 0);

	if (table != NULL)
		luarcu_refget(table);
	return 0;
}

static int luarcu_subscribe(lua_State *L)
{
	luarcu_entry_t *entry;
	size_t keylen;
	const char *key = luaL_checklstring(L, 1, &keylen);
	unsigned int index = luarcu_hash(luarcu_registry, key, keylen);
	luarcu_table_t **ptable = luarcu_newptable(L);

	rcu_read_lock();
	entry = luarcu_lookup(luarcu_registry, index, key, keylen);
	if (entry == NULL) {
		lua_pushnil(L);
		goto out;
	}

	*ptable = (luarcu_table_t *)entry->data;
	luaL_setmetatable(L, LUARCU_MT);
	luarcu_refget(*ptable);
out:
	rcu_read_unlock();
	return 1;
}

static const struct luaL_Reg luarcu_lib[] = {
	{"table", luarcu_table},
	{"publish", luarcu_publish},
	{"subscribe", luarcu_subscribe},
	{NULL, NULL}
};

static const struct luaL_Reg luarcu_mt[] = {
	{"__newindex", luarcu_newindex},
	{"__index", luarcu_index},
	{"__gc", luarcu_delete},
	{"__close", luarcu_delete},
	{NULL, NULL}
};

static const lunatik_class_t luarcu_class = {
	.name = LUARCU_MT,
	.methods = luarcu_mt,
};

LUNATIK_NEWLIB(rcu, luarcu_lib, &luarcu_class, NULL, true);

static int __init luarcu_init(void)
{
	luarcu_registry = luarcu_newtable(LUARCU_DEFAULT_SIZE);
	return 0;
}

static void __exit luarcu_exit(void)
{
	luarcu_refput(luarcu_registry);
}

module_init(luarcu_init);
module_exit(luarcu_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

