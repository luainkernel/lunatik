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

#ifndef LUNATIK_STATES_H
#define LUNATIK_STATES_H

#include "lua/lua.h"
#include "lunatik_conf.h"

struct lunatik_instance {
	struct hlist_head states_table[LUNATIK_HASH_BUCKETS];
	struct reply_buffer *reply_buffer;
	spinlock_t statestable_lock;
	spinlock_t rfcnt_lock;
	spinlock_t sendmessage_lock;
	atomic_t states_count;
};

typedef struct lunatik_state {
	struct hlist_node node;
	lua_State *L;
	luaL_Buffer *buffer;
	spinlock_t lock;
	refcount_t users;
	size_t maxalloc;
	size_t curralloc;
	size_t scriptsize;
	unsigned char name[LUNATIK_NAME_MAXSIZE];
} lunatik_State;

#ifndef LUNATIK_UNUSED
typedef int (*nflua_state_cb)(struct nflua_state *s, unsigned short *total);
#endif /*LUNATIK_UNUSED*/

lunatik_State *lunatik_newstate(size_t maxalloc, const char *name);
int lunatik_close(const char *name);
lunatik_State *lunatik_statelookup(const char *name);

#ifndef LUNATIK_UNUSED
int nflua_state_list(struct xt_lua_net *xt_lua, nflua_state_cb cb,
	unsigned short *total);
#endif /*LUNATIK_UNUSED*/

bool lunatik_stateget(lunatik_State *s);
void lunatik_stateput(lunatik_State *s);

lunatik_State *lunatik_netnewstate(struct lunatik_instance *instance, size_t maxalloc, const char *name);
int lunatik_netclose(struct lunatik_instance *instance, const char *name);
lunatik_State *lunatik_netstatelookup(struct lunatik_instance *instance, const char *name);

#endif /* LUNATIK_STATES_H */
