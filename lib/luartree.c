/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Reverse tree using XArray.
* A tree structure where paths are stored in reverse order for efficient
* prefix sharing (e.g., domain names, file paths).
*
* @module rtree
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/xarray.h>

#include <lunatik.h>

typedef struct luartree_node_s {
	struct xarray children;
	bool is_leaf;
} luartree_node_t;

LUNATIK_PRIVATECHECKER(luartree_check, struct xarray *);

#define luartree_getchild(xa, hash)	((luartree_node_t *)xa_load((xa), (hash)))

static luartree_node_t *luartree_newchild(struct xarray *xa, unsigned long hash, lua_State *L)
{
	luartree_node_t *node = lunatik_checkzalloc(L, sizeof(luartree_node_t));
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));
	
	xa_init(&node->children);
	
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
		xa_erase(xa, index);
		kfree(node);
	}
}

/***
* Inserts a path into the tree.
* @function insert
* @tparam string ... Variable number of labels (path components).
* @treturn nil
* @raise Error if allocation fails.
* @usage t:insert("ai", "claude", "foo")
*/
static int luartree_insert(lua_State *L)
{
	struct xarray *root = luartree_check(L, 1);
	int n = lua_gettop(L) - 1;
	
	if (n == 0)
		goto out;
	
	struct xarray *cur = root;
	luartree_node_t *node = NULL;
	
	for (int i = 2; i <= n + 1; i++) {
		size_t len;
		const char *label = luaL_checklstring(L, i, &len);
		
		unsigned long hash = lunatik_hash(label, len, 0);
		
		node = luartree_getchild(cur, hash);
		if (!node)
			node = luartree_newchild(cur, hash, L);
		
		cur = &node->children;
	}
	
	node->is_leaf = true;
out:
	return 0;
}

/***
* Looks up a path in the tree.
* @function lookup
* @tparam string ... Variable number of labels (path components).
* @treturn boolean `true` if path exists, `false` otherwise.
* @usage local found = t:lookup("ai", "claude", "foo")
*/
static int luartree_lookup(lua_State *L)
{
	struct xarray *root = luartree_check(L, 1);
	
	int n = lua_gettop(L) - 1;
	if (n == 0)
		goto notfound;
	
	struct xarray *cur = root;
	luartree_node_t *node = NULL;
	
	for (int i = 2; i <= n + 1; i++) {
		size_t len;
		const char *label = luaL_checklstring(L, i, &len);
		
		unsigned long hash = lunatik_hash(label, len, 0);
		node = luartree_getchild(cur, hash);
		if (!node)
			goto notfound;
		
		cur = &node->children;
	}
	
	lua_pushboolean(L, node && node->is_leaf);
	return 1;

notfound:
	lua_pushboolean(L, false);
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

