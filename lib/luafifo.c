/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* kfifo (kernel FIFO) implementation.
* This library allows creating and managing fixed-size, lockless FIFO queues
* for byte streams, suitable for producer-consumer scenarios within the kernel.
*
* @module fifo
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kfifo.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

LUNATIK_PRIVATECHECKER(luafifo_check, struct kfifo *);

/***
* Pushes data into the FIFO.
* Copies a string of bytes into the FIFO.
* @function push
* @tparam string data The string containing the bytes to be pushed into the FIFO.
* @treturn nil
* @raise Error if the provided data string is larger than the available space in the FIFO.
* @usage
*   -- Assuming 'myfifo' is a fifo object
*   myfifo:push("hello")
* @see fifo.pop
*/
static int luafifo_push(lua_State *L)
{
	struct kfifo *fifo = luafifo_check(L, 1);
	size_t size;
	const char *buf = luaL_checklstring(L, 2, &size);

	luaL_argcheck(L, size <= kfifo_avail(fifo), 2, "not enough space");
	kfifo_in(fifo, buf, size);
	return 0;
}

/***
* Pops data from the FIFO.
* Retrieves a specified number of bytes from the FIFO.
* @function pop
* @tparam integer size The maximum number of bytes to retrieve from the FIFO.
* @treturn string A string containing the bytes popped from the FIFO. The actual length of this string might be less than `size` if the FIFO contained fewer bytes.
* @treturn integer The actual number of bytes popped from the FIFO.
* @usage
*   -- Assuming 'myfifo' is a fifo object
*   local data, len = myfifo:pop(10)
*   if len > 0 then
*     print("Popped " .. len .. " bytes: " .. data)
*   end
* @see fifo.push
*/
static int luafifo_pop(lua_State *L)
{
	struct kfifo *fifo = luafifo_check(L, 1);
	size_t size = luaL_checkinteger(L, 2);
	luaL_Buffer B;
	char *lbuf = luaL_buffinitsize(L, &B, size);

	size = kfifo_out(fifo, lbuf, size);
	luaL_pushresultsize(&B, size);
	lua_pushinteger(L, (lua_Integer)size);
	return 2;
}

static void luafifo_release(void *private)
{
	struct kfifo *fifo = (struct kfifo *)private;
	kfifo_free(fifo);
}

static int luafifo_new(lua_State *L);

/***
* Represents a kernel FIFO (kfifo) object.
* This is a userdata object returned by `fifo.new()`. It encapsulates
* a `struct kfifo` from the Linux kernel, providing a first-in, first-out
* byte queue.
* @type fifo
*/

/***
* Creates a new kernel FIFO (kfifo) object.
* Allocates and initializes a kfifo of the specified size. The size should
* ideally be a power of two for kfifo's internal optimizations, though kfifo
* will handle non-power-of-two sizes by rounding up.
* @function new
* @tparam integer size The desired capacity of the FIFO in bytes.
* @treturn fifo A new fifo object.
* @raise Error if kfifo allocation fails (e.g., due to insufficient memory).
* @usage
*   local myfifo = fifo.new(1024) -- Creates a FIFO with a capacity of 1024 bytes
* @within fifo
*/
static const luaL_Reg luafifo_lib[] = {
	{"new", luafifo_new},
	{NULL, NULL}
};

/***
* Closes and releases the FIFO object.
* This is an alias for the `__close` and `__gc` metamethods.
* @function close
* @treturn nil
*/
static const luaL_Reg luafifo_mt[] = {
	{"__index", lunatik_monitorobject},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"close", lunatik_closeobject},
	{"push", luafifo_push},
	{"pop", luafifo_pop},
	{NULL, NULL}
};

static const lunatik_class_t luafifo_class = {
	.name = "fifo",
	.methods = luafifo_mt,
	.release = luafifo_release,
	.flags = false,
};

static int luafifo_new(lua_State *L)
{
	size_t size = luaL_checkinteger(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luafifo_class, sizeof(struct kfifo));
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	int ret;

	if ((ret = kfifo_alloc((struct kfifo *)object->private, size, gfp)) != 0)
		luaL_error(L, "failed to allocate kfifo (%d)", ret);
	return 1; /* object */
}

LUNATIK_NEWLIB(fifo, luafifo_lib, &luafifo_class, NULL);

static int __init luafifo_init(void)
{
	return 0;
}

static void __exit luafifo_exit(void)
{
}

module_init(luafifo_init);
module_exit(luafifo_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

