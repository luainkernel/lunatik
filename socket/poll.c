#include "socket.h"
#include <net/sock.h>

#define lpt_len(num)                                                           \
	(sizeof(struct lpoll_table) + (num) * sizeof(struct lpoll_entry))

typedef struct lpoll_table *lpoll_t;

struct lpoll_entry {
	/*
	 * Wait queue item that will be linked to the target file wait
	 * queue head.
	 */
	wait_queue_entry_t wait;

	/* The wait queue head that linked the "wait" wait queue item */
	wait_queue_head_t *whead;

	sock_t socket;

	lpoll_t lpt;
};

struct lpoll_table {
	int num;
	wait_queue_head_t poll_wait;
	struct lpoll_entry *last;
	struct lpoll_entry entries[0];
};

static int lpoll_callback(wait_queue_entry_t *wait, unsigned mode, int sync,
			  void *key)
{
	struct lpoll_entry *lpe = container_of(wait, struct lpoll_entry, wait);
	lpoll_t lpt = lpe->lpt;
	__poll_t pollflags = key_to_poll(key);

	if (pollflags & EPOLLIN) {
		lpt->last = lpe;
		if (waitqueue_active(&lpt->poll_wait))
			wake_up_interruptible(&lpt->poll_wait);
	}

	return 1;
}

int lpoll(lua_State *L)
{
	int num, i;
	struct lpoll_table *lpt;
	luaL_checktype(L, 1, LUA_TTABLE);

	num = luaL_len(L, 1);
	lpt = kmalloc(lpt_len(num), GFP_KERNEL);
	if (lpt == NULL)
		luaL_error(L, "lpoll_table alloc fail.");

	memset(lpt, 0, lpt_len(num));
	lpt->num = num;
	init_waitqueue_head(&lpt->poll_wait);

	for (i = 0; i < num; i++) {
		lua_rawgeti(L, 1, i + 1);
		lpt->entries[i].socket =
		    *(sock_t *) luaL_checkudata(L, -1, LUA_SOCKET);
		lpt->entries[i].lpt = lpt;
		init_waitqueue_func_entry(&lpt->entries[i].wait,
					  lpoll_callback);
		lua_pop(L, 1);
	}

	*((lpoll_t *) lua_newuserdata(L, sizeof(lpoll_t))) = lpt;
	luaL_getmetatable(L, LUA_POLL);
	lua_setmetatable(L, -2);
	return 1;
}

int lpoll_select(lua_State *L)
{
	int i;
	int diff;
	lpoll_t lpt = *(lpoll_t *) luaL_checkudata(L, 1, LUA_POLL);

	lpt->last = NULL;
	for (i = 0; i < lpt->num; i++) {
		struct lpoll_entry *lpe = &lpt->entries[i];

		if (lpe->socket->ops->poll(lpe->socket->file, lpe->socket,
					   NULL) &
		    EPOLLIN) {
			lua_pushinteger(L, i);
			goto remove_wait;
		}
		add_wait_queue(sk_sleep(lpe->socket->sk), &lpe->wait);
	}

	wait_event_interruptible(lpt->poll_wait, lpt->last != NULL);

	diff = (void *) lpt->last - (void *) &lpt->entries;
	BUG_ON((diff % sizeof(struct lpoll_entry)) != 0);

	lua_pushinteger(L, diff / sizeof(struct lpoll_entry));

remove_wait:
	for (i = i - 1; i >= 0; i--) {
		struct lpoll_entry *lpe = &lpt->entries[i];
		remove_wait_queue(sk_sleep(lpe->socket->sk), &lpe->wait);
	}

	return 1;
}

int lpoll_dispose(lua_State *L)
{
	lpoll_t *lpt = (lpoll_t *) luaL_checkudata(L, 1, LUA_POLL);

	if (*lpt == NULL)
		return 0;

	kfree(*lpt);

	*lpt = NULL;

	return 0;
}

static const struct luaL_Reg liblpoll_methods[] = {
    {"select", lpoll_select},
    {"__gc", lpoll_dispose},
    {NULL, NULL} /* sentinel */
};

int luaopen_lpoll(lua_State *L)
{
	luaL_newmetatable(L, LUA_POLL);
	/* Duplicate the metatable on the stack (We know have 2). */
	lua_pushvalue(L, -1);
	/* Pop the first metatable off the stack and assign it to __index
	 * of the second one. We set the metatable for the table to itself.
	 * This is equivalent to the following in lua:
	 * metatable = {}
	 * metatable.__index = metatable
	 */
	lua_setfield(L, -2, "__index");

	/* Set the methods to the metatable that should be accessed via
	 * object:func
	 */
	luaL_setfuncs(L, liblpoll_methods, 0);
	return 1;
}
