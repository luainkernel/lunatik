/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* RCU-synchronized hash table.
* Provides a concurrent hash table using Read-Copy-Update (RCU) synchronization.
* Reads are lockless; writes are serialized. Keys are strings, and a number key is its
* decimal string, so `t[1]` and `t["1"]` are one entry; values can be
* booleans, integers, shareable lunatik objects, or `nil` (to delete an entry). A
* SINGLE object, such as a `device`, a `probe` or a `hid` driver, raises
* `cannot share SINGLE object`, and a string or a table raises `unsupported type`.
* Reading an object returns a new handle on the same kernel object, so two reads of an
* entry compare unequal; from a softirq or
* hardirq runtime, one whose class needs process context raises
* `'<class>': process-context class in interrupt-context runtime`. A read that
* meets a writer releasing the entry's object sees the entry gone. An entry holds its
* object until the entry is overwritten or deleted or the table goes, and a reference
* count does not see a cycle, so storing an `rcu.table` raises `ELOOP` when it is the
* table it is stored in or reaches that table, directly or through the tables it holds;
* it raises `ELOOP` too when it reaches more than 16 tables that hold tables, itself
* included.
*
* A table a probe handler writes is not written from another runtime with interrupts on:
* the writer takes the table's lock with interrupts off only when they already are, so a
* probe that fires inside an interrupt handler on the CPU of a process or softirq writer
* spins on the lock that writer holds.
*
* See `examples/shared/daemon.lua` for a practical example.
* @module rcu
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/spinlock.h>
#include <linux/hashtable.h>
#include <linux/random.h>
#include <linux/srcu.h>

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
* RCU hash table object, indexed as a Lua table.
*
* `t[key]` reads the value (RCU-protected, lockless): `nil` for a key without an
* entry, and for one whose object a writer is releasing.
*
* `t[key] = value` sets the value, and `nil` removes the entry (serialized). A key
* takes up to 255 bytes, and a longer one raises `out of bounds`; a failed
* allocation raises `not enough memory`. The value an assignment replaces or removes
* is released on the assigning task once the table's lock is dropped, so a runtime or a
* socket whose last reference the entry held closes there; when the writer holds a softirq
* or hardirq runtime's lock, which keeps bottom halves or IRQs off, it closes on a
* kernel worker instead.
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
	size_t ntables;
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

#define luarcu_istable(value)		(lunatik_isuserdata(value) && (value)->object->class == &luarcu_class)
#define luarcu_holdstable(entry)	((entry) != NULL && luarcu_istable(&(entry)->value))

DEFINE_STATIC_SRCU(luarcu_srcu);
static DEFINE_SPINLOCK(luarcu_walklock);

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

static void luarcu_freeentry(struct rcu_head *head)
{
	kfree_rcu(container_of(head, luarcu_entry_t, rcu), rcu); /* then the lockless readers' grace period */
}

static inline void luarcu_free(luarcu_entry_t *entry)
{
	if (lunatik_isuserdata(&entry->value))
		lunatik_putobject(entry->value.object);
	call_srcu(&luarcu_srcu, &entry->rcu, luarcu_freeentry);
}

static inline void luarcu_unlink(luarcu_entry_t *old, luarcu_entry_t *new)
{
	if (new) {
		hlist_replace_rcu(&old->hlist, &new->hlist);
		WRITE_ONCE(old->hlist.pprev, NULL); /* the tail of hlist_del_init_rcu, which hlist_replace_rcu lacks */
	}
	else
		hlist_del_init_rcu(&old->hlist);
}

static const lunatik_class_t luarcu_class;

LUNATIK_PRIVATECHECKER(luarcu_checktable, luarcu_table_t *, &luarcu_class);

static inline void luarcu_readvalue(luarcu_entry_t *entry, lunatik_value_t *value)
{
	*value = entry->value;
	if (lunatik_isuserdata(value) && !lunatik_trygetobject(value->object))
		value->type = LUA_TNIL;
}

void luarcu_getvalue(lunatik_object_t *table, const char *key, size_t keylen, lunatik_value_t *value)
{
	luarcu_table_t *_table = (luarcu_table_t *)table->private;
	unsigned int index = luarcu_hash(_table, key, keylen);
	luarcu_entry_t *entry;

	rcu_read_lock();
	if ((entry = luarcu_lookup(_table, index, key, keylen)) == NULL)
		value->type = LUA_TNIL;
	else
		luarcu_readvalue(entry, value);
	rcu_read_unlock();
}
EXPORT_SYMBOL(luarcu_getvalue);

typedef struct luarcu_walk_s {
	lunatik_object_t *target;
	size_t n;
	luarcu_table_t *queue[LUARCU_MAXWALK];
} luarcu_walk_t;

static inline bool luarcu_isqueued(luarcu_walk_t *walk, luarcu_table_t *table)
{
	size_t n = walk->n;

	while (n--)
		if (walk->queue[n] == table)
			return true;
	return false;
}

static int luarcu_queue(luarcu_walk_t *walk, lunatik_object_t *object)
{
	luarcu_table_t *table = (luarcu_table_t *)object->private;

	if (object == walk->target)
		return -ELOOP;
	if (READ_ONCE(table->ntables) == 0 || luarcu_isqueued(walk, table))
		return 0;
	if (walk->n == LUARCU_MAXWALK)
		return -ELOOP;
	walk->queue[walk->n++] = table;
	return 0;
}

static int luarcu_scan(luarcu_walk_t *walk, luarcu_table_t *table)
{
	unsigned int bucket;
	luarcu_entry_t *next, *entry;
	int ret = 0;

	luarcu_foreach(table, bucket, next, entry)
		if (luarcu_istable(&entry->value) && (ret = luarcu_queue(walk, entry->value.object)) < 0)
			break;
	return ret;
}

static int luarcu_walk(lunatik_object_t *object, lunatik_object_t *target)
{
	luarcu_walk_t walk = {.target = target};
	int ret = luarcu_queue(&walk, object);

	rcu_read_lock();
	for (size_t i = 0; i < walk.n && ret == 0; i++)
		ret = luarcu_scan(&walk, walk.queue[i]);
	rcu_read_unlock();
	return ret;
}

static inline void luarcu_waitwalk(void)
{
	unsigned long flags;

	spin_lock_irqsave(&luarcu_walklock, flags);
	spin_unlock_irqrestore(&luarcu_walklock, flags);
}

static inline void luarcu_count(luarcu_table_t *table, luarcu_entry_t *old, luarcu_entry_t *new)
{
	int delta = luarcu_holdstable(new) - luarcu_holdstable(old);

	if (delta != 0)
		WRITE_ONCE(table->ntables, table->ntables + delta);
}

static luarcu_entry_t *luarcu_link(lunatik_object_t *table, const char *key, size_t keylen, luarcu_entry_t *new)
{
	luarcu_table_t *tab = (luarcu_table_t *)table->private;
	luarcu_entry_t *old;
	unsigned int index = luarcu_hash(tab, key, keylen);

	lunatik_lock(table);
	rcu_read_lock();
	old = luarcu_lookup(tab, index, key, keylen);
	rcu_read_unlock();
	if (old)
		luarcu_unlink(old, new);
	else if (new)
		hlist_add_head_rcu(&new->hlist, tab->hlist + index);
	luarcu_count(tab, old, new);
	lunatik_unlock(table);
	return old;
}

static luarcu_entry_t *luarcu_linktable(lunatik_object_t *table, const char *key, size_t keylen, luarcu_entry_t *new)
{
	unsigned long flags;
	luarcu_entry_t *old;
	int ret;

	spin_lock_irqsave(&luarcu_walklock, flags); /* two stores closing one cycle would miss each other */
	ret = luarcu_walk(new->value.object, table);
	old = ret < 0 ? ERR_PTR(ret) : luarcu_link(table, key, keylen, new);
	spin_unlock_irqrestore(&luarcu_walklock, flags);
	return old;
}

int luarcu_setvalue(lunatik_object_t *table, const char *key, size_t keylen, lunatik_value_t *value)
{
	luarcu_entry_t *new = NULL;

	if (value->type != LUA_TNIL && (new = luarcu_newentry(key, keylen, value)) == NULL)
		return -ENOMEM;

	luarcu_entry_t *old = luarcu_istable(value) ?
		luarcu_linktable(table, key, keylen, new) : luarcu_link(table, key, keylen, new);
	if (IS_ERR(old)) {
		luarcu_free(new);
		return PTR_ERR(old);
	}
	if (old != NULL)
		luarcu_free(old); /* the value's put may close a runtime or a socket, which sleeps */
	return 0;
}
EXPORT_SYMBOL(luarcu_setvalue);

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

static int luarcu_newindex(lua_State *L)
{
	lunatik_object_t *table = lunatik_checkobjectclass(L, 1, &luarcu_class);
	size_t keylen;
	const char *key = luaL_checklstring(L, 2, &keylen);
	lunatik_checkbounds(L, 2, keylen, 0, LUARCU_MAXKEY - 1);

	lunatik_value_t value;
	lunatik_checkvalue(L, 3, &value);
	int ret = luarcu_setvalue(table, key, keylen, &value);
	if (ret == -ENOMEM)
		lunatik_enomem(L);
	else if (ret < 0)
		lunatik_throw(L, ret);
	return 0;
}

static void luarcu_release(void *private)
{
	luarcu_table_t *table = (luarcu_table_t *)private;
	unsigned int bucket;
	luarcu_entry_t *n, *entry;

	luarcu_waitwalk(); /* a store's walk that reached this table reads it until the walk ends */
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

static inline void luarcu_readentry(luarcu_entry_t *entry, lunatik_value_t *value)
{
	rcu_read_lock(); /* an unhashed entry's object is freed behind the unhash, after this section */
	if (hlist_unhashed_lockless(&entry->hlist))
		value->type = LUA_TNIL;
	else
		luarcu_readvalue(entry, value);
	rcu_read_unlock();
}

static int luarcu_foreach_handle(lua_State *L)
{
	luarcu_entry_t *entry = (luarcu_entry_t *)lua_touserdata(L, 2);
	lunatik_value_t value;

	BUG_ON(!entry);

	lua_pop(L, 1); /* entry */

	luarcu_readentry(entry, &value); /* a pcall failing before this runs takes no reference */
	if (value.type == LUA_TNIL)
		return 0;

	lunatik_pushvalue(L, &value); /* first, so that a raise below leaves the reference with the clone */
	lua_pushlstring(L, entry->key, entry->keylen);
	lua_insert(L, -2); /* key, value */
	lua_call(L, 2, 0);

	return 0;
}

static inline int luarcu_foreach_call(lua_State *L, int cb, luarcu_entry_t *entry)
{
	lua_pushcfunction(L, luarcu_foreach_handle);
	lua_pushvalue(L, cb);
	lua_pushlightuserdata(L, entry);

	return lua_pcall(L, 2, 0, 0); /* handle(cb, entry) */
}

/***
* Iterates over the table calling `callback(key, value)` for each entry.
* What the callback returns is ignored: it stops the walk early by raising an `error`.
* The walk runs inside an SRCU read-side critical section, which allows the callback
* to sleep; whether it may is its runtime's context, as for any code of a softirq or
* hardirq runtime. A writer on any runtime may change the table meanwhile: an entry
* removed or replaced under the walk may still be reached and is then skipped, one
* added is visited only if its bucket is still ahead, and the order is not guaranteed.
* @function foreach
* @tparam rcu_table t the table to walk
* @tparam function callback `function(key, value)`; an entry whose object a writer is
*   releasing is skipped.
* @raise Error if callback raises.
* @usage rcu.foreach(t, function (key, value) print(key, value) end)
* @within rcu
*/
static int luarcu_lforeach(lua_State *L)
{
	luarcu_table_t *table = luarcu_checktable(L, 1);
	unsigned int bucket;
	luarcu_entry_t *entry;
	int idx, ret = LUA_OK;

	luaL_checktype(L, 2, LUA_TFUNCTION); /* cb */

	idx = srcu_read_lock(&luarcu_srcu);
	for (bucket = 0; bucket < table->size && ret == LUA_OK; bucket++)
		hlist_for_each_entry_srcu(entry, table->hlist + bucket, hlist, srcu_read_lock_held(&luarcu_srcu))
			if ((ret = luarcu_foreach_call(L, 2, entry)) != LUA_OK)
				break;
	srcu_read_unlock(&luarcu_srcu, idx);
	if (ret != LUA_OK)
		lua_error(L);
	return 0;
}

static const struct luaL_Reg luarcu_lib[] = {
	{"table", luarcu_table},
	{"foreach", luarcu_lforeach},
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
	.opt = LUNATIK_OPT_SOFTIRQ,
	.owner = THIS_MODULE,
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
*   the largest count whose table size does not overflow; what memory serves is the allocator's.
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
	srcu_barrier(&luarcu_srcu); /* the queued luarcu_freeentry calls run module text */
}

module_init(luarcu_init);
module_exit(luarcu_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_DESCRIPTION("Lunatik RCU-synchronized hash table");

