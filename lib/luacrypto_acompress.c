/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Crypto API for asynchronous
* compression algorithms (acompress).
*
* This module provides a `new` function to create ACOMPRESS transform objects,
* which can then be used to create requests for compression and decompression.
*
* @module crypto.acompress
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/kernel.h>
#include <linux/module.h>
#include <crypto/acompress.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/limits.h>
#include <linux/completion.h>
#include <linux/scatterlist.h>
#include <linux/version.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <lunatik.h>

#include "luacrypto.h"

/* ACOMPRESS TFM Object */

LUNATIK_PRIVATECHECKER(luacrypto_acompress_check, struct crypto_acomp *);
LUACRYPTO_RELEASER(acompress, struct crypto_acomp, crypto_free_acomp, NULL);

static const luaL_Reg luacrypto_acompress_mt[];

static const lunatik_class_t luacrypto_acompress_class = {
	.name = "crypto_acompress",
	.methods = luacrypto_acompress_mt,
	.release = luacrypto_acompress_release,
	.sleep = true,
	.pointer = true,
};

/* ACOMPRESS Request Object */

typedef struct luacrypto_acomp_req_s {
	struct acomp_req *req;
	struct scatterlist sg_in;
	struct scatterlist sg_out;
	int cb;
	int buf;
	int tfm;
	int self;
	lua_State *L;
	u8 *outbuf;
	size_t outbuf_len;
	bool busy;
} luacrypto_acomp_req_t;

LUNATIK_PRIVATECHECKER(luacrypto_acomp_req_check, luacrypto_acomp_req_t *);

static void luacrypto_acomp_req_release(void *private)
{
	luacrypto_acomp_req_t *obj = (luacrypto_acomp_req_t *)private;

	if (obj->cb != LUA_NOREF) {
		luaL_unref(obj->L, LUA_REGISTRYINDEX, obj->cb);
		obj->cb = LUA_NOREF;
	}

	if (obj->buf != LUA_NOREF) {
		luaL_unref(obj->L, LUA_REGISTRYINDEX, obj->buf);
		obj->buf = LUA_NOREF;
	}

	if (obj->tfm != LUA_NOREF) {
		luaL_unref(obj->L, LUA_REGISTRYINDEX, obj->tfm);
		obj->tfm = LUA_NOREF;
	}

	if (obj->self != LUA_NOREF) {
		luaL_unref(obj->L, LUA_REGISTRYINDEX, obj->self);
		obj->self = LUA_NOREF;
	}

	if (obj->req) {
		acomp_request_free(obj->req);
		obj->req = NULL;
	}

	if (obj->outbuf) {
		lunatik_free(obj->outbuf);
		obj->outbuf = NULL;
	}
}

static int luacrypto_acomp_req_lua_cb(lua_State *L, void *data, int err)
{
	luacrypto_acomp_req_t *obj = (luacrypto_acomp_req_t *)data;

	obj->busy = false;

	if (obj->buf != LUA_NOREF) {
		luaL_unref(L, LUA_REGISTRYINDEX, obj->buf);
		obj->buf = LUA_NOREF;
	}

	if (obj->self != LUA_NOREF) {
		luaL_unref(L, LUA_REGISTRYINDEX, obj->self);
		obj->self = LUA_NOREF;
	}

	if (obj->cb == LUA_NOREF)
		return 0;

	lua_rawgeti(L, LUA_REGISTRYINDEX, obj->cb);
	luaL_unref(L, LUA_REGISTRYINDEX, obj->cb);
	obj->cb = LUA_NOREF;

	if (lua_type(L, -1) != LUA_TFUNCTION) {
		pr_err("No callback function found for acomp request\n");
		lua_pop(L, 1);
		return 0;
	}

	lua_pushinteger(L, err);

	if (err == 0)
		lua_pushlstring(L, (const char *)obj->outbuf, obj->req->dlen);
	else
		lua_pushnil(L);

	if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
		pr_err("Lua callback error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
	return 0;
}

static void luacrypto_acomp_req_docall(void *data, int err)
{
	luacrypto_acomp_req_t *obj = (luacrypto_acomp_req_t *)data;
	lunatik_object_t *runtime = lunatik_toruntime(obj->L);
	int ret;

	lunatik_run(runtime, luacrypto_acomp_req_lua_cb, ret, data, err);
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
#define luacrypto_acomp_request_alloc(tfm, L) ({	\
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));	\
	acomp_request_alloc(tfm, gfp);			\
})
#else
#define luacrypto_acomp_request_alloc(tfm, L)	acomp_request_alloc(tfm)
#endif

static int luacrypto_acomp_req_prepare(luacrypto_acomp_req_t *obj, lua_State *L,
	const char *in_buf, size_t in_len, unsigned int out_len, int cb, int buf)
{
	if (obj->outbuf_len < out_len) {
		if (obj->outbuf)
			lunatik_free(obj->outbuf);
		obj->outbuf = lunatik_checkalloc(L, out_len);
		obj->outbuf_len = out_len;
	}

	sg_init_one(&obj->sg_in, in_buf, in_len);
	sg_init_one(&obj->sg_out, obj->outbuf, out_len);

	acomp_request_set_params(obj->req, &obj->sg_in, &obj->sg_out, in_len, out_len);
	acomp_request_set_callback(obj->req, 0, luacrypto_acomp_req_docall, obj);

	obj->cb = cb;
	obj->buf = buf;
	
	lua_pushvalue(L, 1); /* push self */
	obj->self = luaL_ref(L, LUA_REGISTRYINDEX);
	
	obj->busy = true;
	return 0;
}

#define LUACRYPTO_ACOMP_REQ_OPERATION(name)							\
static int luacrypto_acomp_req_##name(lua_State *L)						\
{												\
	luacrypto_acomp_req_t *obj = luacrypto_acomp_req_check(L, 1);				\
	if (obj->busy)										\
		return luaL_error(L, "request object is busy");					\
												\
	size_t in_len;										\
	const char *in_buf = luaL_checklstring(L, 2, &in_len);					\
	lunatik_checkbounds(L, 2, in_len, 1, UINT_MAX);						\
	unsigned int out_len = lunatik_checkuint(L, 3);						\
	lunatik_checkbounds(L, 3, out_len, 1, UINT_MAX);					\
	luaL_checktype(L, 4, LUA_TFUNCTION);							\
												\
	lua_pushvalue(L, 4);									\
	int cb = luaL_ref(L, LUA_REGISTRYINDEX);						\
	lua_pushvalue(L, 2);									\
	int buf = luaL_ref(L, LUA_REGISTRYINDEX);						\
												\
	lunatik_try(L, luacrypto_acomp_req_prepare, obj, L, in_buf, in_len, out_len, cb, buf);	\
	int ret = crypto_acomp_##name(obj->req);						\
	if (ret != -EINPROGRESS)								\
		luacrypto_acomp_req_docall(obj, ret);						\
	return 0;										\
}

LUACRYPTO_ACOMP_REQ_OPERATION(compress)
LUACRYPTO_ACOMP_REQ_OPERATION(decompress)

static const luaL_Reg luacrypto_acomp_req_mt[] = {
	{"compress", luacrypto_acomp_req_compress},
	{"decompress", luacrypto_acomp_req_decompress},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_acomp_req_class = {
	.name = "crypto_acomp_req",
	.methods = luacrypto_acomp_req_mt,
	.release = luacrypto_acomp_req_release,
	.sleep = true,
};

/* ACOMPRESS TFM Methods */

static int luacrypto_acompress_request(lua_State *L)
{
	struct crypto_acomp *tfm = luacrypto_acompress_check(L, 1);
	lunatik_object_t *object;
	luacrypto_acomp_req_t *req;

	object = lunatik_newobject(L, &luacrypto_acomp_req_class, sizeof(luacrypto_acomp_req_t));
	req = (luacrypto_acomp_req_t *)object->private;

	memset(req, 0, sizeof(luacrypto_acomp_req_t));
	req->L = L;
	req->cb = LUA_NOREF;
	req->buf = LUA_NOREF;
	req->self = LUA_NOREF;
	
	lua_pushvalue(L, 1); /* push TFM object */
	req->tfm = luaL_ref(L, LUA_REGISTRYINDEX);

	req->req = luacrypto_acomp_request_alloc(tfm, L);
	if (!req->req)
		return luaL_error(L, "failed to allocate acomp request");

	return 1;
}

static const luaL_Reg luacrypto_acompress_mt[] = {
	{"request", luacrypto_acompress_request},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

/* Module Init */

static int luacrypto_acompress_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_acompress_class, 0);
	struct crypto_acomp *tfm;

	tfm = crypto_alloc_acomp(algname, 0, 0);
	if (IS_ERR(tfm)) {
		long err = PTR_ERR(tfm);
		luaL_error(L, "Failed to allocate acompress transform for %s (err %ld)", algname, err);
	}
	object->private = tfm;

	return 1;
}

static const luaL_Reg luacrypto_acompress_lib[] = {
	{"new", luacrypto_acompress_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB_MULTICLASS(crypto_acompress, luacrypto_acompress_lib,
	((const lunatik_class_t[]){
		luacrypto_acompress_class,
		luacrypto_acomp_req_class,
		{NULL}
	}), NULL);

static int __init luacrypto_acompress_init(void)
{
	return 0;
}

static void __exit luacrypto_acompress_exit(void)
{
}

module_init(luacrypto_acompress_init);
module_exit(luacrypto_acompress_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("jperon <cataclop@hotmail.com>");
MODULE_DESCRIPTION("Lunatik low-level Linux Crypto API interface (ACOMPRESS)");

