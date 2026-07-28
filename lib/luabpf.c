/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to eBPF.
*
* This module provides access to pinned eBPF maps of two kinds:
*
* Key-value maps, via `lookup`, `update`, `delete`, `remove`, and `next`:
*   - BPF_MAP_TYPE_HASH
*   - BPF_MAP_TYPE_ARRAY
*   - BPF_MAP_TYPE_LRU_HASH
*
* Queue/stack maps, via `push`, `pop`, and `peek`:
*   - BPF_MAP_TYPE_QUEUE (FIFO)
*   - BPF_MAP_TYPE_STACK (LIFO)
*
* Other map types are rejected when opened. Calling an operation that a
* map type does not implement (e.g. `lookup` on a queue) raises an
* `EOPNOTSUPP` error.
*
* Keys and values are exchanged as packed Lua strings whose sizes must
* match the map's configured key and value sizes. Queue/stack maps have
* no keys, so only `value_size` applies to them.
*
* @module bpf
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/bpf.h>
#include <linux/namei.h>
#include <linux/fs.h>

#include <lunatik.h>

LUNATIK_PRIVATECHECKER(luabpf_map_check, struct bpf_map *);

#define luabpf_map_issupported(type)	\
	((type) == BPF_MAP_TYPE_HASH || (type) == BPF_MAP_TYPE_ARRAY || (type) == BPF_MAP_TYPE_LRU_HASH || \
	 (type) == BPF_MAP_TYPE_QUEUE || (type) == BPF_MAP_TYPE_STACK)

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

static struct bpf_map *luabpf_map_get(lua_State *L, const char *pathname)
{
	struct path path;
	lunatik_try(L, kern_path, pathname, LOOKUP_FOLLOW, &path);

	struct bpf_map *map = luabpf_map_frompath(&path);
	if (map)
		bpf_map_inc(map);

	path_put(&path);
	return map;
}

/***
* Represents an open eBPF map handle.
* This is a userdata object returned by `bpf.map()`. It holds a
* reference to a pinned `struct bpf_map`.
* The length operator (`#map`) returns the map's `max_entries`.
* @type map
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

	if (map->ops->map_lookup_and_delete_elem == NULL)
		lunatik_throw(L, -EOPNOTSUPP);

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
*   local map = require("bpf").map
*   local flow = map("/sys/fs/bpf/flow_cache")
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
* Pushes a value onto a queue or stack map.
* @function push
* @tparam string value Packed value.
* @tparam[opt=0] integer flags Update flags. `BPF_EXIST` may be set to
* overwrite the oldest element once the map is full.
* @treturn boolean success
* @raise Error if the map does not support this operation (e.g. hash/array maps).
*/
static int luabpf_map_push(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	const char *value = luabpf_map_checkvalue(L, map, 2);
	u64 flags = luaL_optinteger(L, 3, 0);

	long ret;
	luabpf_map_call(ret, map->ops->map_push_elem(map, (void *)value, flags));
	return luabpf_map_pushresult(L, ret);
}

/***
* Pops (removes and returns) the next value from a queue or stack map.
* Queue maps pop in FIFO order; stack maps pop in LIFO order.
* @function pop
* @treturn string value Packed value, or `nil` if the map is empty.
* @raise Error if the map does not support this operation (e.g. hash/array maps).
*/
static int luabpf_map_pop(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	luaL_Buffer B;
	char *value = luaL_buffinitsize(L, &B, map->value_size);

	long ret;
	luabpf_map_call(ret, map->ops->map_pop_elem(map, value));
	return luabpf_map_pushbuffer(L, &B, map->value_size, ret);
}

/***
* Peeks at the next value of a queue or stack map without removing it.
* @function peek
* @treturn string value Packed value, or `nil` if the map is empty.
* @raise Error if the map does not support this operation (e.g. hash/array maps).
*/
static int luabpf_map_peek(lua_State *L)
{
	struct bpf_map *map = luabpf_map_check(L, 1);
	luaL_Buffer B;
	char *value = luaL_buffinitsize(L, &B, map->value_size);

	long ret;
	luabpf_map_call(ret, map->ops->map_peek_elem(map, value));
	return luabpf_map_pushbuffer(L, &B, map->value_size, ret);
}

/***
* Returns the map properties.
* @function info
* @treturn table `type`, `key_size`, `value_size` and `max_entries`,
* named as in the kernel's `struct bpf_map_info`.
*/
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

/***
* Releases the map reference.
* This is an alias for the `__close` metamethod.
* @function close
*/
static const luaL_Reg luabpf_map_mt[] = {
	{"lookup",  luabpf_map_lookup},
	{"update",  luabpf_map_update},
	{"delete",  luabpf_map_delete},
	{"remove",  luabpf_map_remove},
	{"next",    luabpf_map_next},
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

static const lunatik_class_t luabpf_map_class = {
	.name = "bpf_map",
	.methods = luabpf_map_mt,
	.release = luabpf_map_release,
	.opt = LUNATIK_OPT_EXTERNAL | LUNATIK_OPT_HARDIRQ,
};

/***
* Opens a map from a pinned bpffs path.
* @function map
* @tparam string path Path to a pinned eBPF map.
* @treturn map Opened map handle.
* @raise Error if the path does not resolve to a supported pinned eBPF map.
* Path lookup may sleep, so on interrupt-context runtimes (softirq/hardirq)
* `map` is only allowed during script load; the returned handle can then be
* used from handlers.
* @usage
*   local bpf = require("bpf")
*   local counter = bpf.map("/sys/fs/bpf/counters")
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
*
*   -- Queue/stack maps have no keys; use push/pop/peek instead.
*   local jobs = bpf.map("/sys/fs/bpf/job_queue")
*   assert(jobs:push(string.pack("I4", 7)))
*   local job = jobs:peek()          -- inspect without removing
*   job = jobs:pop()                 -- remove and return
*   jobs:close()
* @within bpf
*/
static int luabpf_map_open(lua_State *L)
{
	lunatik_object_t *runtime = lunatik_toruntime(L);
	luaL_argcheck(L, !lunatik_isirq(runtime->opt) || !lunatik_isready(runtime), 1, "not allowed after module load");
	const char *pathname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luabpf_map_class, 0, LUNATIK_OPT_NONE);
	struct bpf_map *map = luabpf_map_get(L, pathname);

	object->private = map;
	luaL_argcheck(L, map != NULL, 1, "not a bpf map");
	luaL_argcheck(L, luabpf_map_issupported(map->map_type), 1, "unsupported map type");
	return 1;
}

static const luaL_Reg luabpf_lib[] = {
	{"map", luabpf_map_open},
	{NULL, NULL}
};

LUNATIK_CLASSES(bpf, &luabpf_map_class);
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

