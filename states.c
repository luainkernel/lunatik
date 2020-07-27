/*
 * Copyright (C) 2020  Matheus Rodrigues <matheussr61@gmail.com>
 * Copyright (C) 2017-2019  CUJO LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/slab.h>
#include <linux/spinlock.h>
#include <linux/idr.h>
#include <linux/ratelimit.h>
#include <linux/hashtable.h>
#include <linux/stringhash.h>

#include "lua/lualib.h"

#include "luautil.h"
#include "states.h"

#ifndef LUNATIK_SETPAUSE
#define LUNATIK_SETPAUSE	100
#endif /* LUNATIK_SETPAUSE */

static struct lunatik_instance instance;

static inline int name_hash(void *salt, const char *name)
{
	int len = strnlen(name, LUNATIK_NAME_MAXSIZE);
	return full_name_hash(salt, name, len) & (LUNATIK_HASH_BUCKETS - 1);
}

lunatik_State *lunatik_statelookup(const char *name)
{
	lunatik_State *state;
	int key = name_hash(&instance, name);

	hash_for_each_possible_rcu(instance.states_table, state, node, key) {
		if (!strncmp(state->name, name, LUNATIK_NAME_MAXSIZE))
			return state;
	}
	return NULL;
}

void state_destroy(lunatik_State *s)
{
	hash_del_rcu(&s->node);
	atomic_dec(&(instance.states_count));

	spin_lock_bh(&s->lock);
	if (s->L != NULL) {
		lua_close(s->L);
		s->L = NULL;
	}
	spin_unlock_bh(&s->lock);

	lunatik_stateput(s);
}

static void *lua_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	lunatik_State *s = ud;
	void *nptr = NULL;

	/* osize doesn't represent the object old size if ptr is NULL */
	osize = ptr != NULL ? osize : 0;

	if (nsize == 0) {
		s->curralloc -= osize;
		kfree(ptr);
	} else if (s->curralloc - osize + nsize > s->maxalloc) {
		pr_warn_ratelimited("maxalloc limit %zu reached on state %.*s\n",
		    s->maxalloc, LUNATIK_NAME_MAXSIZE, s->name);
	} else if ((nptr = krealloc(ptr, nsize, GFP_ATOMIC)) != NULL) {
		s->curralloc += nsize - osize;
	}

	return nptr;
}

static int state_init(lunatik_State *s)
{
	#ifndef LUNATIK_UNUSED
	const luaL_Reg *lib;
	#endif /*LUNATIK_UNUSED*/

	s->L = lua_newstate(lua_alloc, s);
	if (s->L == NULL)
		return -ENOMEM;

	luaU_setenv(s->L, s, lunatik_State);
	luaL_openlibs(s->L);

	#ifndef LUNATIK_UNUSED
	for (lib = libs; lib->name != NULL; lib++) {
		luaL_requiref(s->L, lib->name, lib->func, 1);
		lua_pop(s->L, 1);
	}
	#endif

	/* fixes an issue where the Lua's GC enters a vicious cycle.
	 * more info here: https://marc.info/?l=lua-l&m=155024035605499&w=2
	 */
	lua_gc(s->L, LUA_GCSETPAUSE, LUNATIK_SETPAUSE);

	return 0;
}

lunatik_State *lunatik_newstate(size_t maxalloc, const char *name)
{
	lunatik_State *s = lunatik_statelookup(name);
	int namelen = strnlen(name, LUNATIK_NAME_MAXSIZE);

	pr_debug("creating state: %.*s maxalloc: %zd\n", namelen, name,
		maxalloc);

	if (s != NULL) {
		pr_err("state already exists: %.*s\n", namelen, name);
		return NULL;
	}

	if (atomic_read(&(instance.states_count)) >= LUNATIK_HASH_BUCKETS) {
		pr_err("could not allocate id for state %.*s\n", namelen, name);
		pr_err("max states limit reached or out of memory\n");
		return NULL;
	}

	if (maxalloc < LUNATIK_MIN_ALLOC_BYTES) {
		pr_err("maxalloc %zu should be greater then MIN_ALLOC %zu\n",
		    maxalloc, LUNATIK_MIN_ALLOC_BYTES);
		return NULL;
	}

	if ((s = kzalloc(sizeof(lunatik_State), GFP_ATOMIC)) == NULL) {
		pr_err("could not allocate nflua state\n");
		return NULL;
	}

	spin_lock_init(&s->lock);
	#ifndef LUNATIK_UNUSED
	s->dseqnum   = 0;
	#endif
	s->maxalloc  = maxalloc;
	s->curralloc = 0;
	memcpy(&(s->name), name, namelen);

	if (state_init(s)) {
		pr_err("could not allocate a new lua state\n");
		kfree(s);
		return NULL;
	}

	spin_lock_bh(&(instance.statestable_lock));
	hash_add_rcu(instance.states_table, &(s->node), name_hash(&instance, name));
	refcount_inc(&s->users);
	atomic_inc(&(instance.states_count));
	spin_unlock_bh(&(instance.statestable_lock));

	pr_debug("new state created: %.*s\n", namelen, name);
	return s;
}

int lunatik_close(const char *name)
{
	lunatik_State *s = lunatik_statelookup(name);

	if (s == NULL || refcount_read(&s->users) > 1)
		return -1;

	spin_lock_bh(&(instance.statestable_lock));
	state_destroy(s);
	spin_unlock_bh(&(instance.statestable_lock));

	return 0;
}

void lunatik_closeall(void)
{
	struct hlist_node *tmp;
	lunatik_State *s;
	int bkt;

	spin_lock_bh(&(instance.statestable_lock));
	hash_for_each_safe (instance.states_table, bkt, tmp, s, node) {
		state_destroy(s);
	}
	spin_unlock_bh(&(instance.statestable_lock));
}

inline bool lunatik_stateget(lunatik_State *s)
{
	return refcount_inc_not_zero(&s->users);
}

void lunatik_stateput(lunatik_State *s)
{
	refcount_t *users = &s->users;
	spinlock_t *refcnt_lock = &(instance.rfcnt_lock);

	if (WARN_ON(s == NULL))
		return;

	if (refcount_dec_not_one(users))
		return;

	spin_lock_bh(refcnt_lock);
	if (!refcount_dec_and_test(users))
		goto out;

	kfree(s);
out:
	spin_unlock_bh(refcnt_lock);
}

void lunatik_statesinit(void)
{
	atomic_set(&(instance.states_count), 0);
	spin_lock_init(&(instance.statestable_lock));
	spin_lock_init(&(instance.rfcnt_lock));
	hash_init(instance.states_table);
}

lunatik_State *lunatik_netstatelookup(struct lunatik_instance *instance, const char *name)
{

	lunatik_State *state;
	int key;
	if (instance == NULL)
		return NULL;

	key = name_hash(instance,name);

	hash_for_each_possible_rcu(instance->states_table, state, node, key) {
		if (!strncmp(state->name, name, LUNATIK_NAME_MAXSIZE))
			return state;
	}
	return NULL;
}

lunatik_State *lunatik_netnewstate(struct lunatik_instance *instance, size_t maxalloc, const char *name)
{

	lunatik_State *s = lunatik_netstatelookup(instance, name);
	int namelen = strnlen(name, LUNATIK_NAME_MAXSIZE);

	pr_debug("creating state: %.*s maxalloc: %zd\n", namelen, name,
		maxalloc);

	if (s != NULL) {
		pr_err("state already exists: %.*s\n", namelen, name);
		return NULL;
	}

	if (atomic_read(&(instance->states_count)) >= LUNATIK_HASH_BUCKETS) {
		pr_err("could not allocate id for state %.*s\n", namelen, name);
		pr_err("max states limit reached or out of memory\n");
		return NULL;
	}

	if (maxalloc < LUNATIK_MIN_ALLOC_BYTES) {
		pr_err("maxalloc %zu should be greater then MIN_ALLOC %zu\n",
		    maxalloc, LUNATIK_MIN_ALLOC_BYTES);
		return NULL;
	}

	if ((s = kzalloc(sizeof(lunatik_State), GFP_ATOMIC)) == NULL) {
		pr_err("could not allocate nflua state\n");
		return NULL;
	}

	spin_lock_init(&s->lock);
	s->maxalloc  = maxalloc;
	s->curralloc = 0;
	memcpy(&(s->name), name, namelen);

	if (state_init(s)) {
		pr_err("could not allocate a new lua state\n");
		kfree(s);
		return NULL;
	}

	spin_lock_bh(&(instance->statestable_lock));
	hash_add_rcu(instance->states_table, &(s->node), name_hash(instance,name));
	refcount_inc(&(s->users));
	atomic_inc(&(instance->states_count));
	spin_unlock_bh(&(instance->statestable_lock));

	pr_debug("new state created: %.*s\n", namelen, name);
	return s;
}

int lunatik_netclose(struct lunatik_instance *instance, const char *name)
{
	lunatik_State *s = lunatik_netstatelookup(instance,name);

	if (s == NULL || refcount_read(&s->users) > 1)
		return -1;

	spin_lock_bh(&(instance->statestable_lock));

	hash_del_rcu(&s->node);
	atomic_dec(&(instance->states_count));

	spin_lock_bh(&s->lock);
	if (s->L != NULL) {
		lua_close(s->L);
		s->L = NULL;
	}
	spin_unlock_bh(&s->lock);
	lunatik_stateput(s);

	spin_unlock_bh(&(instance->statestable_lock));

	return 0;
}

