/*
* SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface for eBPF maps.
*
* This module provides generic key-value access to pinned eBPF maps,
* supporting types that implement standard lookup, update, deletion,
* and iteration operations, including:
*   - BPF_MAP_TYPE_HASH
*   - BPF_MAP_TYPE_ARRAY
*   - BPF_MAP_TYPE_LRU_HASH
*
* Keys and values are exchanged as packed Lua strings whose sizes must
* match the map's configured key and value sizes.
*
* @module ebpf.map
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/bpf.h>
#include <linux/namei.h>
#include <linux/fs.h>

#include <lunatik.h>

LUNATIK_PRIVATECHECKER(luaebpf_map_check, struct bpf_map *,
	luaL_argcheck(L, private != NULL, ix, "bpf map is not set");
);

#define luaebpf_map_checksize(L, size, expected, ix, arg) \
	luaL_argcheck((L), (size) == (expected), (ix), "invalid " arg " size")

static int luaebpf_map_pushresult(lua_State *L, long ret)
{
	if (ret == -ENOENT) {
		lua_pushboolean(L, 0);
		return 1;
	}
	if (ret)
		lunatik_throw(L, ret);
	lua_pushboolean(L, 1);
	return 1;
}

#define luaebpf_map_checkret(L, ret, cleanup) \
do { \
	if ((ret) == -ENOENT) { \
		cleanup; \
		lua_pushnil(L); \
		return 1; \
	} \
	if (ret) { \
		cleanup; \
		lunatik_throw(L, ret); \
	} \
} while (0)

static void luaebpf_map_release(void *private);

static inline struct bpf_map *luaebpf_map_frompath(const struct path *path)
{
	struct inode *inode = d_inode(path->dentry);
	return inode ? inode->i_private : NULL;
}

static struct bpf_map *luaebpf_map_get(const char *pathname)
{
	struct path path;

	if (kern_path(pathname, LOOKUP_FOLLOW, &path))
		return NULL;

	struct bpf_map *map = luaebpf_map_frompath(&path);
	if (map)
		bpf_map_inc(map);

	path_put(&path);
	return map;
}

/**
* Looks up a key from the map.
* @function lookup
* @tparam map map
* @tparam string key Packed key
* @treturn string value Packed value, or `nil` if the key is not present
*/
static int luaebpf_map_lookup(lua_State *L)
{
	struct bpf_map *map = luaebpf_map_check(L, 1);
	size_t key_size;
	const char *key = luaL_checklstring(L, 2, &key_size);
	luaebpf_map_checksize(L, key_size, map->key_size, 2, "key");

	void *value = map->ops->map_lookup_elem(map, (void *)key);

	if (!value)
		lua_pushnil(L);
	else
		lua_pushlstring(L, value, map->value_size);
	return 1;
}

/**
* Updates a key in the map.
* @function update
* @tparam map map
* @tparam string key Packed key.
* @tparam string value Packed value.
* @tparam[opt=BPF_ANY] integer flags Update flags. One of:
*   - `BPF_ANY` (default): Create a new element or update an existing one.
*   - `BPF_NOEXIST`: Create a new element only if the key does not exist.
*   - `BPF_EXIST`: Update an existing element only if the key exists.
* @treturn boolean success
* @raise Error if the operation is not permitted by the map.
*/
static int luaebpf_map_update(lua_State *L)
{
	struct bpf_map *map= luaebpf_map_check(L, 1);
	size_t key_size;
	const char *key = luaL_checklstring(L, 2, &key_size);
	size_t value_size;
	const char *value = luaL_checklstring(L, 3, &value_size);

	luaebpf_map_checksize(L, key_size, map->key_size, 2, "key");
	luaebpf_map_checksize(L, value_size, map->value_size, 3, "value");
	u64 flags = luaL_optinteger(L, 4, BPF_ANY);

	if (flags != BPF_ANY && flags != BPF_NOEXIST && flags != BPF_EXIST)
		luaL_argerror(L, 4, "invalid update flag");

	long ret = map->ops->map_update_elem(map, (void *)key, (void *)value, flags);
	return luaebpf_map_pushresult(L, ret);
}

/**
* Deletes a key from the map.
* @function delete
* @tparam map map
* @tparam string key Packed key.
* @treturn boolean success
* @raise Error if the operation is not permitted by the map.
*/
static int luaebpf_map_delete(lua_State *L)
{
	struct bpf_map *map = luaebpf_map_check(L, 1);
	size_t key_size;
	const char *key = luaL_checklstring(L, 2, &key_size);

	luaebpf_map_checksize(L, key_size, map->key_size, 2, "key");

	long ret = map->ops->map_delete_elem(map, (void *)key);
	return luaebpf_map_pushresult(L, ret);
}

/**
* Looks up and deletes a key from the map.
* @function remove
* @tparam map map
* @tparam string key Packed key.
* @treturn string value Packed value, or `nil` if the key is not present.
* @raise Error if the operation is not permitted by the map or memory allocation fails.
*/
static int luaebpf_map_remove(lua_State *L)
{
	struct bpf_map *map = luaebpf_map_check(L, 1);
	size_t key_size;
	const char *key = luaL_checklstring(L, 2, &key_size);

	luaebpf_map_checksize(L, key_size, map->key_size, 2, "key");

	char *value = lunatik_checkalloc(L, map->value_size);
	int ret = map->ops->map_lookup_and_delete_elem(map, (void *)key, (void *)value, 0);

	luaebpf_map_checkret(L, ret, kfree(value));
	lua_pushlstring(L, value, map->value_size);
	kfree(value);
	return 1;
}

/**
* Returns the next key in the map.
* @function get_next_key
* @tparam map map
* @tparam[opt] string key Packed key, returns the first key if nothing is passed.
* @treturn string next_key Packed next key, or `nil` if there are no more keys.
* @raise Error if the operation is not permitted by the map or memory allocation fails.
* @usage
*   local map = require("ebpf.map")
*   local flow = map.open("/sys/fs/bpf/flow_cache")
*   local key = flow:get_next_key()
*   while key do
*   	print(key)
*   	key = flow:get_next_key(key)
*   end
*   flow:close()
*/
static int luaebpf_map_get_next_key(lua_State *L)
{
	struct bpf_map *map = luaebpf_map_check(L, 1);
	size_t key_size;
	const char *key = luaL_optlstring(L, 2, NULL, &key_size);
	luaL_argcheck(L, (key_size == map->key_size) || (key_size == 0), 2, "invalid key size");
	void *next_key = lunatik_checkalloc(L, map->key_size);
	long ret = map->ops->map_get_next_key(map, (void *)key, next_key);

	luaebpf_map_checkret(L, ret, kfree(next_key));
	lua_pushlstring(L, next_key, map->key_size);
	kfree(next_key);
	return 1;
}

/**
* Releases the map reference.
* @function close
*/
static int luaebpf_map_close(lua_State *L)
{
	lunatik_object_t *obj = lunatik_checkobject(L, 1);
	struct bpf_map *map = obj->private;
	if (map) {
		obj->private = NULL;
		bpf_map_put(map);
	}
	return 0;
}

static const luaL_Reg luaebpf_map_mt[] = {
	{"lookup",       luaebpf_map_lookup},
	{"update",       luaebpf_map_update},
	{"delete",       luaebpf_map_delete},
	{"remove",       luaebpf_map_remove},
	{"get_next_key", luaebpf_map_get_next_key},
	{"close",        luaebpf_map_close},
	{"__gc",         lunatik_deleteobject},
	{NULL, NULL}
};

LUNATIK_OPENER(ebpf_map);
static const lunatik_class_t luaebpf_map_class = {
	.name = "ebpf_map",
	.methods = luaebpf_map_mt,
	.release = luaebpf_map_release,
	.opener = luaopen_ebpf_map,
	.opt = LUNATIK_OPT_SOFTIRQ | LUNATIK_OPT_SINGLE,
};

/**
* Opens a map from pinned bpffs path.
*
* @function open
* @tparam string path Path to a pinned eBPF map.
* @treturn map map Opened map handle.
* @usage
*   local map = require("ebpf.map")
*   local bpf = require("linux.bpf")
*   local counter = map.open("/sys/fs/bpf/counters")
*   -- 32-bit key/value encoded as packed strings.
*   local key = string.pack("I4", 1)
*   local value = string.pack("I4", 42)
*   assert(counter:update(key, value, bpf.ANY))
*   local result = counter:lookup(key)
*   if result then
*       print(string.unpack("I4", result))
*   end
*   counter:delete(key)
*   counter:close()
*/
static int luaebpf_map_open(lua_State *L)
{
	const char *pathname = luaL_checkstring(L, 1);
	struct bpf_map *map = luaebpf_map_get(pathname);
	luaL_argcheck(L, map != NULL, 1, "failed to open bpf map");
	lunatik_object_t *object = lunatik_newobject(L, &luaebpf_map_class, sizeof(struct bpf_map *), LUNATIK_OPT_NONE);
	object->private = map;
	return 1;
}

static const luaL_Reg luaebpf_map_lib[] = {
	{"open", luaebpf_map_open},
	{NULL, NULL},
};

static void luaebpf_map_release(void *private)
{
	struct bpf_map *map = (struct bpf_map *)private;
	if (map)
		bpf_map_put(map);
}

LUNATIK_CLASSES(ebpf_map, &luaebpf_map_class);
LUNATIK_NEWLIB(ebpf_map, luaebpf_map_lib, luaebpf_map_classes);

static int __init luaebpf_map_init(void)
{
	return 0;
}

static void __exit luaebpf_map_exit(void)
{
}

module_init(luaebpf_map_init);
module_exit(luaebpf_map_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>");

