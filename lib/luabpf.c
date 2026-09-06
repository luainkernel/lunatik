/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to eBPF.
*
* This module provides typed access to pinned eBPF maps; one
* constructor per map type, each validating the type on open:
*
* `hash`, `array` and `lru_hash` open key-value maps, with `lookup`,
* `update`, `delete`, `remove` and `next`.
*
* `queue` (FIFO) and `stack` (LIFO) open keyless maps, with `push`,
* `pop` and `peek`.
*
* Keys and values are exchanged as packed Lua strings whose sizes must
* match the map's configured key and value sizes. Queues and stacks
* have no keys, so only `value_size` applies to them.
*
* @module bpf
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/bpf.h>
#include <linux/namei.h>
#include <linux/fs.h>

#include <lunatik.h>

static const lunatik_class_t luabpf_hash_class;
static const lunatik_class_t luabpf_queue_class;

LUNATIK_PRIVATECHECKERS(luabpf_map_check, struct bpf_map *, "bpf.map", &luabpf_hash_class, &luabpf_queue_class);

#define luabpf_map_istype(map, type)	((map) != NULL && (map)->map_type == (type))

static const struct inode_operations *luabpf_map_iops;

static const char *luabpf_map_checklstring(lua_State *L, int ix, size_t expected, const char *what)
{
	size_t size;
	const char *s = luaL_checklstring(L, ix, &size);
	if (size != expected)
		luaL_argerror(L, ix, lua_pushfstring(L, "invalid %s size", what));
	return s;
}

#define luabpf_map_checkkey(L, map, ix)		luabpf_map_checklstring((L), (ix), (map)->key_size, "key")
#define luabpf_map_checkvalue(L, map, ix)	luabpf_map_checklstring((L), (ix), (map)->value_size, "value")

static const char *luabpf_map_optkey(lua_State *L, struct bpf_map *map, int ix)
{
	size_t size;
	const char *key = luaL_optlstring(L, ix, NULL, &size);
	luaL_argcheck(L, key == NULL || size == map->key_size, ix, "invalid key size");
	return key;
}

#define luabpf_map_call(ret, op)	\
do {					\
	rcu_read_lock();		\
	ret = (op);			\
	rcu_read_unlock();		\
} while (0)

static inline void luabpf_map_checkret(lua_State *L, long ret)
{
	if (ret < 0 && ret != -ENOENT && ret != -EEXIST)
		lunatik_throw(L, ret);
}

static inline void luabpf_map_checkop(lua_State *L, const void *op)
{
	if (op == NULL)
		lunatik_throw(L, -EOPNOTSUPP);
}

static int luabpf_map_pushresult(lua_State *L, long ret)
{
	luabpf_map_checkret(L, ret);
	lua_pushboolean(L, ret == 0);
	return 1;
}

static int luabpf_map_pushbuffer(lua_State *L, luaL_Buffer *B, size_t size, long ret)
{
	luabpf_map_checkret(L, ret);
	ret == 0 ? luaL_pushresultsize(B, size) : lua_pushnil(L);
	return 1;
}

static inline struct bpf_map *luabpf_map_frompath(const struct path *path)
{
	struct inode *inode = d_inode(path->dentry);
	return inode->i_op == luabpf_map_iops ? inode->i_private : NULL;
}

static struct bpf_map *luabpf_map_get(lua_State *L, const char *pathname, enum bpf_map_type type)
{
	struct path path;
	lunatik_try(L, kern_path, pathname, LOOKUP_FOLLOW, &path);

	struct bpf_map *map = luabpf_map_frompath(&path);
	if (luabpf_map_istype(map, type))
		bpf_map_inc(map);
	else
		map = NULL;

	path_put(&path);
	return map;
}

/***
* Represents an open key-value map handle.
* This is a userdata object returned by `bpf.hash()`, `bpf.array()` and
* `bpf.lru_hash()`. It holds a reference to a pinned `struct bpf_map`.
* The length operator (`#t`) returns the map's `max_entries`.
* @type bpf_hash
*/

static long luabpf_map_copyvalue(struct bpf_map *map, const char *key, char *value)
{
	void *ptr = map->ops->map_lookup_elem(map, (void *)key);
	if (IS_ERR_OR_NULL(ptr))
		return ptr ? PTR_ERR(ptr) : -ENOENT;

	copy_map_value(map, value, ptr);
	check_and_init_map_value(map, value);
	return 0;
}

/***
* Looks up a key from the map.
* @function lookup
* @tparam string key Packed key.
* @treturn string value Packed value, or `nil` if the key is not present.
* @raise Error if the operation fails.
*/
static int luabpf_map_lookup(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	const char *key = luabpf_map_checkkey(L, map, 2);
	luaL_Buffer B;
	char *value = luaL_buffinitsize(L, &B, map->value_size);

	long ret;
	luabpf_map_call(ret, luabpf_map_copyvalue(map, key, value));
	return luabpf_map_pushbuffer(L, &B, map->value_size, ret);
}

/***
* Updates a key in the map.
* @function update
* @tparam string key Packed key.
* @tparam string value Packed value.
* @tparam[opt=BPF_ANY] integer flags Update flags. One of:
*   - `BPF_ANY` (default): Create a new element or update an existing one.
*   - `BPF_NOEXIST`: Create a new element only if the key does not exist.
*   - `BPF_EXIST`: Update an existing element only if the key exists.
* @treturn boolean success; `false` when the flag condition is not met
* (`BPF_EXIST` on an absent key, `BPF_NOEXIST` on a present one).
* @raise Error if the operation is not permitted by the map.
*/
static int luabpf_map_update(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	const char *key = luabpf_map_checkkey(L, map, 2);
	const char *value = luabpf_map_checkvalue(L, map, 3);
	u64 flags = luaL_optinteger(L, 4, BPF_ANY);

	long ret;
	luabpf_map_call(ret, map->ops->map_update_elem(map, (void *)key, (void *)value, flags));
	return luabpf_map_pushresult(L, ret);
}

/***
* Deletes a key from the map.
* @function delete
* @tparam string key Packed key.
* @treturn boolean success
* @raise Error if the operation is not permitted by the map.
*/
static int luabpf_map_delete(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	const char *key = luabpf_map_checkkey(L, map, 2);

	long ret;
	luabpf_map_call(ret, map->ops->map_delete_elem(map, (void *)key));
	return luabpf_map_pushresult(L, ret);
}

/***
* Looks up and deletes a key from the map.
* @function remove
* @tparam string key Packed key.
* @treturn string value Packed value, or `nil` if the key is not present.
* @raise Error if the operation is not supported by the map (e.g. array maps).
*/
static int luabpf_map_remove(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	const char *key = luabpf_map_checkkey(L, map, 2);

	luabpf_map_checkop(L, map->ops->map_lookup_and_delete_elem);

	luaL_Buffer B;
	char *value = luaL_buffinitsize(L, &B, map->value_size);

	long ret;
	luabpf_map_call(ret, map->ops->map_lookup_and_delete_elem(map, (void *)key, value, 0));
	return luabpf_map_pushbuffer(L, &B, map->value_size, ret);
}

/***
* Returns the next key in the map.
* Mirrors Lua's `next(t, key)`, so it can drive a generic `for` directly.
* @function next
* @tparam[opt] string key Packed key; returns the first key if nothing is passed.
* @treturn string next_key Packed next key, or `nil` if there are no more keys.
* @raise Error if the operation fails.
* @usage
*   local hash = require("bpf").hash
*   local flow = hash("/sys/fs/bpf/flow_cache")
*   for key in flow.next, flow do
*   	print(key)
*   end
*   flow:close()
*/
static int luabpf_map_next(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	const char *key = luabpf_map_optkey(L, map, 2);

	luaL_Buffer B;
	char *next_key = luaL_buffinitsize(L, &B, map->key_size);

	long ret;
	luabpf_map_call(ret, map->ops->map_get_next_key(map, (void *)key, next_key));
	return luabpf_map_pushbuffer(L, &B, map->key_size, ret);
}

/***
* Returns the map properties.
* @function info
* @treturn table `type`, `key_size`, `value_size` and `max_entries`,
* named as in the kernel's `struct bpf_map_info`.
*/

/***
* Releases the map reference.
* This is an alias for the `__close` metamethod.
* @function close
*/

/***
* Represents an open queue or stack handle, as returned by `bpf.queue()`
* and `bpf.stack()`. It also exposes `info`, `close` and the length
* operator, as `bpf_hash`.
* @type bpf_queue
*/

/***
* Pushes a value onto the map.
* @function push
* @tparam string value Packed value.
* @tparam[opt=BPF_ANY] integer flags Update flags. `BPF_EXIST` may be set to
* overwrite the oldest element once the map is full.
* @treturn boolean success; `false` when the map is full and `BPF_EXIST`
* was not given.
* @raise Error on invalid flags.
*/
static int luabpf_map_push(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	const char *value = luabpf_map_checkvalue(L, map, 2);
	u64 flags = luaL_optinteger(L, 3, BPF_ANY);

	luabpf_map_checkop(L, map->ops->map_push_elem);

	long ret;
	luabpf_map_call(ret, map->ops->map_push_elem(map, (void *)value, flags));
	if (ret == -E2BIG) {
		lua_pushboolean(L, 0);
		return 1;
	}
	return luabpf_map_pushresult(L, ret);
}

#define LUABPF_MAP_GETTER(name, op)						\
static int luabpf_map_##name(lua_State *L)					\
{										\
	struct bpf_map *map = luabpf_map_check(L, 1);				\
	luabpf_map_checkop(L, map->ops->op);					\
										\
	luaL_Buffer B;								\
	char *value = luaL_buffinitsize(L, &B, map->value_size);		\
										\
	long ret;								\
	luabpf_map_call(ret, map->ops->op(map, value));				\
	return luabpf_map_pushbuffer(L, &B, map->value_size, ret);		\
}

/***
* Pops (removes and returns) the next value from the map.
* Queues pop in FIFO order; stacks pop in LIFO order.
* @function pop
* @treturn string value Packed value, or `nil` if the map is empty.
*/
LUABPF_MAP_GETTER(pop, map_pop_elem)

/***
* Peeks at the next value of the map without removing it.
* @function peek
* @treturn string value Packed value, or `nil` if the map is empty.
*/
LUABPF_MAP_GETTER(peek, map_peek_elem)

static int luabpf_map_info(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);

	lua_createtable(L, 0, 4);
	lua_pushinteger(L, map->map_type);
	lua_setfield(L, -2, "type");
	lua_pushinteger(L, map->key_size);
	lua_setfield(L, -2, "key_size");
	lua_pushinteger(L, map->value_size);
	lua_setfield(L, -2, "value_size");
	lua_pushinteger(L, map->max_entries);
	lua_setfield(L, -2, "max_entries");
	return 1;
}

static int luabpf_map_len(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	lua_pushinteger(L, map->max_entries);
	return 1;
}

static void luabpf_map_release(void *private)
{
	bpf_map_put((struct bpf_map *)private);
}

static const luaL_Reg luabpf_hash_mt[] = {
	{"lookup",  luabpf_map_lookup},
	{"update",  luabpf_map_update},
	{"delete",  luabpf_map_delete},
	{"remove",  luabpf_map_remove},
	{"next",    luabpf_map_next},
	{"info",    luabpf_map_info},
	{"close",   lunatik_closeobject},
	{"__len",   luabpf_map_len},
	{"__close", lunatik_closeobject},
	{"__gc",    lunatik_deleteobject},
	{NULL, NULL}
};

static const luaL_Reg luabpf_queue_mt[] = {
	{"push",    luabpf_map_push},
	{"pop",     luabpf_map_pop},
	{"peek",    luabpf_map_peek},
	{"info",    luabpf_map_info},
	{"close",   lunatik_closeobject},
	{"__len",   luabpf_map_len},
	{"__close", lunatik_closeobject},
	{"__gc",    lunatik_deleteobject},
	{NULL, NULL}
};

static const lunatik_class_t luabpf_hash_class = {
	.name = "bpf_hash",
	.methods = luabpf_hash_mt,
	.release = luabpf_map_release,
	.opt = LUNATIK_OPT_EXTERNAL | LUNATIK_OPT_HARDIRQ,
};

static const lunatik_class_t luabpf_queue_class = {
	.name = "bpf_queue",
	.methods = luabpf_queue_mt,
	.release = luabpf_map_release,
	.opt = LUNATIK_OPT_EXTERNAL | LUNATIK_OPT_HARDIRQ,
};

static int luabpf_open(lua_State *L, const lunatik_class_t *class, enum bpf_map_type type,
	const char *expected)
{
	if (unlikely(lunatik_cannotsleep(L, lunatik_isready(lunatik_toruntime(L)))))
		luaL_argerror(L, 1, "not allowed after module load");

	const char *pathname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, class, 0, LUNATIK_OPT_NONE);

	object->private = luabpf_map_get(L, pathname, type);
	luaL_argcheck(L, object->private != NULL, 1, expected);
	return 1;
}

#define LUABPF_OPENER(name, class, TYPE)						\
static int luabpf_##name##_open(lua_State *L)						\
{											\
	return luabpf_open(L, &luabpf_##class##_class, BPF_MAP_TYPE_##TYPE,		\
		#name " map expected");							\
}

/***
* Opens a hash map from a pinned bpffs path.
* @function hash
* @tparam string path Path to a pinned eBPF hash map.
* @treturn bpf_hash Opened map handle.
* @raise Error if the path does not resolve to a pinned eBPF hash map.
* Path lookup may sleep, so on interrupt-context runtimes (softirq/hardirq)
* the constructors are only allowed during script load; the returned handle
* can then be used from handlers.
* @usage
*   local bpf = require("bpf")
*   local counter = bpf.hash("/sys/fs/bpf/counters")
*   -- 32-bit key/value encoded as packed strings.
*   local key = string.pack("I4", 1)
*   local value = string.pack("I4", 42)
*   assert(counter:update(key, value))
*   local result = counter:lookup(key)
*   if result then
*       print(string.unpack("I4", result))
*   end
*   counter:delete(key)
*   counter:close()
* @within bpf
*/
LUABPF_OPENER(hash, hash, HASH)

/***
* Opens an array map from a pinned bpffs path.
* Keys are 32-bit indexes, packed as 4-byte strings.
* Same interrupt-context restriction as `hash`.
* @function array
* @tparam string path Path to a pinned eBPF array map.
* @treturn bpf_hash Opened map handle.
* @raise Error if the path does not resolve to a pinned eBPF array map.
* @within bpf
*/
LUABPF_OPENER(array, hash, ARRAY)

/***
* Opens an LRU hash map from a pinned bpffs path.
* Same interrupt-context restriction as `hash`.
* @function lru_hash
* @tparam string path Path to a pinned eBPF LRU hash map.
* @treturn bpf_hash Opened map handle.
* @raise Error if the path does not resolve to a pinned eBPF LRU hash map.
* @within bpf
*/
LUABPF_OPENER(lru_hash, hash, LRU_HASH)

/***
* Opens a queue (FIFO) map from a pinned bpffs path.
* Same interrupt-context restriction as `hash`.
* @function queue
* @tparam string path Path to a pinned eBPF queue map.
* @treturn bpf_queue Opened queue handle.
* @raise Error if the path does not resolve to a pinned eBPF queue map.
* @usage
*   local bpf = require("bpf")
*   local jobs = bpf.queue("/sys/fs/bpf/job_queue")
*   assert(jobs:push(string.pack("I4", 7)))
*   local job = jobs:peek()          -- inspect without removing
*   job = jobs:pop()                 -- remove and return
*   jobs:close()
* @within bpf
*/
LUABPF_OPENER(queue, queue, QUEUE)

/***
* Opens a stack (LIFO) map from a pinned bpffs path.
* Same interrupt-context restriction as `hash`.
* @function stack
* @tparam string path Path to a pinned eBPF stack map.
* @treturn bpf_queue Opened stack handle.
* @raise Error if the path does not resolve to a pinned eBPF stack map.
* @within bpf
*/
LUABPF_OPENER(stack, queue, STACK)

static const luaL_Reg luabpf_lib[] = {
	{"hash",     luabpf_hash_open},
	{"array",    luabpf_array_open},
	{"lru_hash", luabpf_lru_hash_open},
	{"queue",    luabpf_queue_open},
	{"stack",    luabpf_stack_open},
	{NULL, NULL}
};

LUNATIK_CLASSES(bpf, &luabpf_hash_class, &luabpf_queue_class);
LUNATIK_NEWLIB(bpf, luabpf_lib, luabpf_classes);

static int __init luabpf_init(void)
{
	if ((luabpf_map_iops = (const struct inode_operations *)lunatik_lookup("bpf_map_iops")) == NULL)
		return -ENXIO;
	return 0;
}

static void __exit luabpf_exit(void)
{
}

module_init(luabpf_init);
module_exit(luabpf_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>");
MODULE_DESCRIPTION("Lunatik interface to eBPF");

