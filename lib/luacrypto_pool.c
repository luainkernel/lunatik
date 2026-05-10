/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/aead.h>
#include <crypto/skcipher.h>
#include <linux/hashtable.h>
#include <linux/list.h>
#include <linux/slab.h>

#include "luacrypto.h"

#define LUACRYPTO_POOL_BUCKET_BITS	6
#define LUACRYPTO_POOL_MAX_PER_BUCKET	32

typedef struct luacrypto_req_node_s {
	struct list_head list;
	void *request;
} luacrypto_req_node_t;

typedef struct luacrypto_req_bucket_s {
	struct hlist_node hnode;
	u8 type;
	unsigned int reqsize;
	unsigned int depth;
	struct list_head free_list;
} luacrypto_req_bucket_t;

typedef struct luacrypto_runtime_pool_s {
	lunatik_opt_t opt;
	union {
		struct mutex mutex;
		spinlock_t spin;
	};
	unsigned long flags;
	gfp_t gfp;
	DECLARE_HASHTABLE(buckets, LUACRYPTO_POOL_BUCKET_BITS);
} luacrypto_runtime_pool_t;

static char luacrypto_pool_registry_key;
static const char *luacrypto_pool_mt = "crypto.request_pool";

static inline u32 luacrypto_pool_hash(enum luacrypto_request_type type, unsigned int reqsize)
{
	return ((u32)type << 24) ^ reqsize;
}

static inline void *luacrypto_request_alloc(enum luacrypto_request_type type, void *tfm, gfp_t gfp)
{
	if (type == LUACRYPTO_REQUEST_SKCIPHER)
		return skcipher_request_alloc((struct crypto_skcipher *)tfm, gfp);
	return aead_request_alloc((struct crypto_aead *)tfm, gfp);
}

static inline void luacrypto_request_free(enum luacrypto_request_type type, void *request)
{
	if (request == NULL)
		return;
	if (type == LUACRYPTO_REQUEST_SKCIPHER)
		skcipher_request_free((struct skcipher_request *)request);
	else
		aead_request_free((struct aead_request *)request);
}

static inline void luacrypto_request_prepare(enum luacrypto_request_type type, void *request,
	void *tfm)
{
	if (type == LUACRYPTO_REQUEST_SKCIPHER) {
		skcipher_request_set_tfm((struct skcipher_request *)request,
			(struct crypto_skcipher *)tfm);
		return;
	}

	aead_request_set_tfm((struct aead_request *)request, (struct crypto_aead *)tfm);
}

static luacrypto_req_bucket_t *luacrypto_pool_find_locked(luacrypto_runtime_pool_t *pool,
	enum luacrypto_request_type type, unsigned int reqsize)
{
	u32 key = luacrypto_pool_hash(type, reqsize);
	luacrypto_req_bucket_t *bucket;

	hash_for_each_possible(pool->buckets, bucket, hnode, key) {
		if (bucket->type == type && bucket->reqsize == reqsize)
			return bucket;
	}
	return NULL;
}

static inline luacrypto_req_bucket_t *luacrypto_pool_alloc_bucket(luacrypto_runtime_pool_t *pool,
	enum luacrypto_request_type type, unsigned int reqsize)
{
	luacrypto_req_bucket_t *bucket = kzalloc(sizeof(*bucket), pool->gfp);
	if (bucket == NULL)
		return NULL;
	bucket->type = type;
	bucket->reqsize = reqsize;
	INIT_LIST_HEAD(&bucket->free_list);
	return bucket;
}

static void luacrypto_pool_destroy(luacrypto_runtime_pool_t *pool)
{
	unsigned int bkt;
	luacrypto_req_bucket_t *bucket;
	struct hlist_node *tmp;

	hash_for_each_safe(pool->buckets, bkt, tmp, bucket, hnode) {
		luacrypto_req_node_t *node, *next;
		list_for_each_entry_safe(node, next, &bucket->free_list, list) {
			list_del(&node->list);
			luacrypto_request_free((enum luacrypto_request_type)bucket->type, node->request);
			lunatik_free(node);
		}
		hash_del(&bucket->hnode);
		lunatik_free(bucket);
	}

	lunatik_freelock(pool);
	lunatik_free(pool);
}

static int luacrypto_pool_gc(lua_State *L)
{
	luacrypto_runtime_pool_t **ppool = (luacrypto_runtime_pool_t **)lua_touserdata(L, 1);

	if (ppool && *ppool) {
		luacrypto_pool_destroy(*ppool);
		*ppool = NULL;
	}
	return 0;
}

static inline void luacrypto_pool_metatable(lua_State *L)
{
	if (luaL_newmetatable(L, luacrypto_pool_mt) != 0) {
		lua_pushcfunction(L, luacrypto_pool_gc);
		lua_setfield(L, -2, "__gc");
	}
	lua_pop(L, 1);
}

static luacrypto_runtime_pool_t *luacrypto_pool_lookup(lua_State *L)
{
	luacrypto_runtime_pool_t *pool = NULL;
	luacrypto_runtime_pool_t **ppool;

	lunatik_getregistry(L, &luacrypto_pool_registry_key);
	if (lua_isuserdata(L, -1)) {
		ppool = (luacrypto_runtime_pool_t **)lua_touserdata(L, -1);
		pool = ppool ? *ppool : NULL;
	}
	lua_pop(L, 1);

	return pool;
}

static luacrypto_runtime_pool_t *luacrypto_pool_get(lua_State *L)
{
	lunatik_object_t *runtime = lunatik_toruntime(L);
	luacrypto_runtime_pool_t *pool = luacrypto_pool_lookup(L);
	luacrypto_runtime_pool_t **ppool;

	if (pool)
		return pool;

	lunatik_getregistry(L, &luacrypto_pool_registry_key);
	if (lua_isuserdata(L, -1)) {
		ppool = (luacrypto_runtime_pool_t **)lua_touserdata(L, -1);
		pool = ppool ? *ppool : NULL;
	}
	lua_pop(L, 1);
	if (pool)
		return pool;

	pool = kzalloc(sizeof(*pool), lunatik_gfp(runtime));
	if (pool == NULL)
		return NULL;

	pool->opt = runtime->opt;
	pool->gfp = lunatik_gfp(runtime);
	hash_init(pool->buckets);
	lunatik_newlock(pool);
	luacrypto_pool_metatable(L);

	ppool = (luacrypto_runtime_pool_t **)lua_newuserdatauv(L, sizeof(*ppool), 0);
	*ppool = pool;
	luaL_getmetatable(L, luacrypto_pool_mt);
	lua_setmetatable(L, -2);
	lua_rawsetp(L, LUA_REGISTRYINDEX, &luacrypto_pool_registry_key);

	return pool;
}

void *luacrypto_request_pool_acquire(lua_State *L, enum luacrypto_request_type type,
	void *tfm, unsigned int reqsize)
{
	luacrypto_runtime_pool_t *pool = luacrypto_pool_get(L);
	void *request = NULL;

	if (pool == NULL)
		return luacrypto_request_alloc(type, tfm, lunatik_gfp(lunatik_toruntime(L)));

	lunatik_lock(pool);
	luacrypto_req_bucket_t *bucket = luacrypto_pool_find_locked(pool, type, reqsize);
	if (bucket && !list_empty(&bucket->free_list)) {
		luacrypto_req_node_t *node = list_first_entry(&bucket->free_list, luacrypto_req_node_t, list);
		list_del(&node->list);
		bucket->depth--;
		request = node->request;
		lunatik_free(node);
		lunatik_unlock(pool);
		luacrypto_request_prepare(type, request, tfm);
		return request;
	}
	lunatik_unlock(pool);

	request = luacrypto_request_alloc(type, tfm, pool->gfp);
	if (request)
		luacrypto_request_prepare(type, request, tfm);

	return request;
}
EXPORT_SYMBOL_GPL(luacrypto_request_pool_acquire);

void luacrypto_request_pool_release(lua_State *L, enum luacrypto_request_type type,
	void *request, unsigned int reqsize)
{
	luacrypto_runtime_pool_t *pool;
	luacrypto_req_bucket_t *bucket;
	luacrypto_req_bucket_t *new_bucket = NULL;
	luacrypto_req_node_t *node;

	if (request == NULL)
		return;

	pool = luacrypto_pool_lookup(L);
	if (pool == NULL) {
		luacrypto_request_free(type, request);
		return;
	}

	node = kzalloc(sizeof(*node), pool->gfp);
	if (node == NULL) {
		luacrypto_request_free(type, request);
		return;
	}
	node->request = request;

	lunatik_lock(pool);
	bucket = luacrypto_pool_find_locked(pool, type, reqsize);
	if (bucket == NULL) {
		lunatik_unlock(pool);
		new_bucket = luacrypto_pool_alloc_bucket(pool, type, reqsize);
		lunatik_lock(pool);
		bucket = luacrypto_pool_find_locked(pool, type, reqsize);
		if (bucket == NULL && new_bucket) {
			u32 key = luacrypto_pool_hash(type, reqsize);
			hash_add(pool->buckets, &new_bucket->hnode, key);
			bucket = new_bucket;
			new_bucket = NULL;
		}
	}

	if (bucket && bucket->depth < LUACRYPTO_POOL_MAX_PER_BUCKET) {
		list_add(&node->list, &bucket->free_list);
		bucket->depth++;
		node = NULL;
	}
	lunatik_unlock(pool);

	lunatik_free(new_bucket);
	if (node) {
		luacrypto_request_free(type, request);
		lunatik_free(node);
	}
}
EXPORT_SYMBOL_GPL(luacrypto_request_pool_release);
