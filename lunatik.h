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

#ifndef lunatik_h
#define lunatik_h

#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/slab.h>

#include <lua.h>
#include <lauxlib.h>

#define lunatik_locker(extra, spin_op, mutex_op)	\
do {							\
	if (extra->sleep)				\
		mutex_op(&extra->lock.mutex);		\
	else						\
		spin_op(&extra->lock.spin);		\
} while(0)

#define lunatik_getextra(L)	((lunatik_extra_t *)lua_getextraspace(L))
#define lunatik_lock(L)		lunatik_locker(lunatik_getextra(L), spin_lock, mutex_lock)
#define lunatik_unlock(L)	lunatik_locker(lunatik_getextra(L), spin_unlock, mutex_unlock)

static inline lua_State *lunatik_newstate(bool sleep)
{
	lua_State *L;
	if ((L = luaL_newstate()) != NULL) {
		lunatik_extra_t *extra;
		extra = lunatik_getextra(L);
		extra->sleep = sleep;
		lunatik_locker(extra, spin_lock_init, mutex_init);
	}
	return L;
}

static inline void lunatik_close(lua_State *L)
{
	lunatik_extra_t *extra;
	extra = lunatik_getextra(L);
	if (extra->sleep)
		mutex_destroy(&extra->lock.mutex);
	lua_close(L);
}

#define lunatik_run(L, handler, ret, ...)	\
do {						\
	int n;					\
	lunatik_lock(L);			\
	n = lua_gettop(L);			\
	ret = handler(L, ## __VA_ARGS__);	\
	lua_settop(L, n);			\
	lunatik_unlock(L);			\
} while(0)

/* based on l_alloc() @ lua/lauxlib.c */
static inline void *lunatik_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
	lunatik_extra_t *extra;
	(void)osize;  /* not used */

	if (nsize == 0) {
		kfree(ptr);
		return NULL;
	}
	extra = (lunatik_extra_t *)ud;
	return krealloc(ptr, nsize, extra->sleep ? GFP_KERNEL : GFP_ATOMIC);
}
#define lunatik_setalloc(L)	lua_setallocf(L, lunatik_alloc, lunatik_getextra(L))

#endif

