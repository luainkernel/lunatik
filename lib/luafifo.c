/*
* SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* kfifo (kernel FIFO) implementation.
* This library allows creating and managing fixed-size FIFO queues for byte
* streams, suitable for producer-consumer scenarios within the kernel. Each call
* takes the object's lock, so one fifo can be shared between runtimes, as through
* `runtime:resume`, and used from softirq.
*
* @module fifo
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kfifo.h>

#include <lunatik.h>

static const lunatik_class_t luafifo_class;

LUNATIK_PRIVATECHECKER(luafifo_check, struct kfifo *, &luafifo_class);

/***
* Represents a kernel FIFO (kfifo) object.
* This is a userdata object returned by `fifo.new()`. It encapsulates
* a `struct kfifo` from the Linux kernel, providing a first-in, first-out
* byte queue.
* @type fifo
*/

/***
* Pushes data into the FIFO.
* Copies a string of bytes into the FIFO, whole or not at all.
* @function push
* @tparam string data bytes to push into the FIFO, up to its capacity.
* @treturn boolean `true` if the FIFO took the bytes, `false` if it has no room for them all.
* @raise "out of bounds" for a string longer than the FIFO's capacity, which no pop makes room for.
* @usage
*   -- Assuming 'myfifo' is a fifo object
*   if not myfifo:push("hello") then
*     print("full")
*   end
* @see fifo.pop
*/
static int luafifo_push(lua_State *L)
{
	struct kfifo *fifo = luafifo_check(L, 1);
	size_t size;
	const char *buf = luaL_checklstring(L, 2, &size);

	lunatik_checkbounds(L, 2, size, 0, kfifo_size(fifo));
	bool fits = size <= kfifo_avail(fifo);
	if (fits)
		kfifo_in(fifo, buf, size);
	lua_pushboolean(L, fits);
	return 1;
}

/***
* Pops data from the FIFO.
* Retrieves a specified number of bytes from the FIFO.
* @function pop
* @tparam integer size maximum number of bytes to retrieve from the FIFO, up to its capacity.
* @treturn string A string containing the bytes popped from the FIFO. The actual length of this string might be less than `size` if the FIFO contained fewer bytes.
* @treturn integer actual number of bytes popped from the FIFO.
* @raise Error if `size` is out of bounds.
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
	size_t size = (size_t)lunatik_checkinteger(L, 2, 0, kfifo_size(fifo));
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
	lunatik_free(fifo->kfifo.data);
}

static int luafifo_new(lua_State *L);

/***
* Creates a new kernel FIFO (kfifo) object.
* Allocates and initializes a kfifo of the specified size. The size should
* ideally be a power of two for kfifo's internal optimizations, though a
* non-power-of-two size is rounded up. In a process runtime, and in the body
* of a softirq or hardirq runtime, a buffer larger than a page may come from
* vmalloc, which needs no physically contiguous pages; past that body, the
* buffer needs them.
* @function new
* @tparam integer size desired capacity of the FIFO in bytes, from 2 up to `KMALLOC_MAX_SIZE`.
* @treturn fifo A new fifo object.
* @raise Error if `size` is out of bounds; "not enough memory" if the kernel cannot allocate the buffer.
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
* It also runs when a to-be-closed variable holding the object goes out of scope. Later calls raise
* "closed object".
* @function close
* @treturn nil
* @raise "not allowed with IRQs disabled" when called with IRQs disabled, as in every callback of a
*   hardirq runtime, a probe's handlers among them, where a buffer from vmalloc cannot be freed, and
*   so does the end of the scope of a `<close>` variable holding the fifo there; the fifo is then
*   released with its last reference.
*/
static const luaL_Reg luafifo_mt[] = {
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
	.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_MONITOR,
	.owner = THIS_MODULE,
};

static int luafifo_new(lua_State *L)
{
	size_t size = roundup_pow_of_two(lunatik_checkinteger(L, 1, 2, KMALLOC_MAX_SIZE));
	lunatik_object_t *object = lunatik_newobject(L, &luafifo_class, sizeof(struct kfifo), LUNATIK_OPT_NONE);
	void *buffer = lunatik_checkalloc(L, size);

	kfifo_init((struct kfifo *)object->private, buffer, size);
	return 1; /* object */
}

LUNATIK_CLASSES(fifo, &luafifo_class);
LUNATIK_NEWLIB(fifo, luafifo_lib, luafifo_classes);

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
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_DESCRIPTION("Lunatik interface to kfifo");

