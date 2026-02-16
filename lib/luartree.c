/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Reverse tree with Lua values using XArray.
* A tree structure where paths are stored in reverse order with Lua values
* at each node (string, number, boolean, or nil).
*
* @module rtree
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/xarray.h>

#include <lunatik.h>

typedef struct luartree_node_s {
	struct xarray children;
	int type;
	union {
		lua_Integer i;
		bool b;
		const char *s;
	} value;
} luartree_node_t;

LUNATIK_PRIVATECHECKER(luartree_check, struct xarray *);

#define luartree_getchild(xa, hash)	((luartree_node_t *)xa_load((xa), (hash)))

static luartree_node_t *luartree_newchild(struct xarray *xa, unsigned long hash, lua_State *L)
{
	luartree_node_t *node = lunatik_checkzalloc(L, sizeof(luartree_node_t));
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));

	xa_init(&node->children);
	node->type = LUA_TNIL;

	void *old = xa_store(xa, hash, node, gfp);
	if (xa_is_err(old)) {
		lunatik_free(node);
		return NULL;
	}
	return node;
}

static void luartree_freetree(struct xarray *xa)
{
	unsigned long index;
	luartree_node_t *node;

	xa_for_each(xa, index, node) {
		luartree_freetree(&node->children);
		if (node->type == LUA_TSTRING)
			lunatik_free(node->value.s);
		xa_erase(xa, index);
		lunatik_free(node);
	}
}

static void luartree_tonode(lua_State *L, luartree_node_t *node, int idx)
{
	if (node->type == LUA_TSTRING)
		lunatik_free((void *)node->value.s);

	node->type = lua_type(L, idx);
	switch (node->type) {
	case LUA_TNUMBER:
		node->value.i = lua_tointeger(L, idx);
		break;
	case LUA_TBOOLEAN:
		node->value.b = lua_toboolean(L, idx);
		break;
	case LUA_TSTRING: {
		size_t len;
		const char *s = lua_tolstring(L, idx, &len);
		char *str = lunatik_checkalloc(L, len + 1);
		memcpy(str, s, len + 1);
		node->value.s = str;
		break;
	}
	case LUA_TNIL:
		break;
	default:
		luaL_error(L, "unsupported type: %s", lua_typename(L, node->type));
	}
}

static void luartree_pushnode(lua_State *L, luartree_node_t *node)
{
	switch (node->type) {
	case LUA_TNUMBER:
		lua_pushinteger(L, node->value.i);
		break;
	case LUA_TBOOLEAN:
		lua_pushboolean(L, node->value.b);
		break;
	case LUA_TSTRING:
		lua_pushstring(L, node->value.s);
		break;
	case LUA_TNIL:
	default:
		lua_pushnil(L);
		break;
	}
}

/***
* Inserts a path with a value into the tree.
* @function insert
* @tparam any value The value to store (string, number, boolean, or nil).
* @tparam string ... Variable number of labels (path components).
* @treturn nil
* @raise Error if allocation fails.
* @usage t:insert("hello", "ai", "claude", "foo")
* @usage t:insert(42, "ai", "claude", "bar")
* @usage t:insert(true, "ai", "claude", "baz")
*/
static int luartree_insert(lua_State *L)
{
	struct xarray *root = luartree_check(L, 1);
	int n = lua_gettop(L) - 2;

	if (n < 1)
		luaL_error(L, "insert requires value and path");

	struct xarray *xa = root;
	luartree_node_t *node = NULL;

	for (int i = 3; i <= n + 2; i++) {
		size_t len;
		const char *label = luaL_checklstring(L, i, &len);
		unsigned long hash = lunatik_hash(label, len, 0);

		node = luartree_getchild(xa, hash);
		if (!node)
			node = luartree_newchild(xa, hash, L);

		xa = &node->children;
	}

	luartree_tonode(L, node, 2);
	return 0;
}

/***
* Looks up a path and returns its value.
* @function lookup
* @tparam string ... Variable number of labels (path components).
* @treturn any The value stored at the path, or nil if not found.
* @usage local value = t:lookup("ai", "claude", "foo")
*/
static int luartree_lookup(lua_State *L)
{
	struct xarray *root = luartree_check(L, 1);
	int n = lua_gettop(L) - 1;

	if (n == 0)
		goto notfound;

	struct xarray *xa = root;
	luartree_node_t *node = NULL;

	for (int i = 2; i <= n + 1; i++) {
		size_t len;
		const char *label = luaL_checklstring(L, i, &len);
		unsigned long hash = lunatik_hash(label, len, 0);

		node = luartree_getchild(xa, hash);
		if (!node)
			goto notfound;

		xa = &node->children;
	}

	if (node) {
		luartree_pushnode(L, node);
		return 1;
	}

notfound:
	lua_pushnil(L);
	return 1;
}

static void luartree_release(void *private)
{
	struct xarray *root = (struct xarray *)private;
	luartree_freetree(root);
	xa_destroy(root);
}

static int luartree_new(lua_State *L);

/***
* Reverse tree object.
* @type rtree
*/

/***
* Creates a new reverse tree.
* @function new
* @treturn rtree A new empty tree.
* @usage local t = rtree.new()
* @within rtree
*/
static const luaL_Reg luartree_lib[] = {
	{"new", luartree_new},
	{NULL, NULL}
};

static const luaL_Reg luartree_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"close", lunatik_closeobject},
	{"insert", luartree_insert},
	{"lookup", luartree_lookup},
	{NULL, NULL}
};

static const lunatik_class_t luartree_class = {
	.name = "rtree",
	.methods = luartree_mt,
	.release = luartree_release,
	.sleep = false,
	.shared = true,
};

static int luartree_new(lua_State *L)
{
	lunatik_object_t *object = lunatik_newobject(L, &luartree_class, sizeof(struct xarray));
	struct xarray *root = (struct xarray *)object->private;

	xa_init(root);
	return 1;
}

LUNATIK_NEWLIB(rtree, luartree_lib, &luartree_class, NULL);

static int __init luartree_init(void)
{
	return 0;
}

static void __exit luartree_exit(void)
{
}

module_init(luartree_init);
module_exit(luartree_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");
MODULE_AUTHOR("Claude <noreply@anthropic.com>");

