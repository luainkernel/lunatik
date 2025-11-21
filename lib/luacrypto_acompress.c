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
	int refs;
	lunatik_object_t *runtime;
	u8 *outbuf;
	size_t outbuf_len;
	bool busy;
} luacrypto_acomp_req_t;

LUNATIK_PRIVATECHECKER(luacrypto_acomp_req_check, luacrypto_acomp_req_t *);

static void luacrypto_acomp_req_release(void *private)
{
	luacrypto_acomp_req_t *obj = (luacrypto_acomp_req_t *)private;

	if (obj->runtime) {
		lua_State *L = lunatik_getstate(obj->runtime);

		if (L && obj->refs != LUA_NOREF) {
			luaL_unref(L, LUA_REGISTRYINDEX, obj->refs);
			obj->refs = LUA_NOREF;
		}

		lunatik_putobject(obj->runtime);
		obj->runtime = NULL;
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

/* Helper function that will be called via pcall to safely push arguments and call callback */
static int luacrypto_acomp_req_call_cb(lua_State *L)
{
	luacrypto_acomp_req_t *obj = (luacrypto_acomp_req_t *)lua_touserdata(L, 1);
	int err = lua_tointeger(L, 2);

	/* Get the refs table */
	lua_rawgeti(L, LUA_REGISTRYINDEX, obj->refs);
	if (lua_type(L, -1) != LUA_TTABLE) {
		pr_err("No refs table found for acomp request\n");
		return 0;
	}

	/* Get the callback function from the table */
	lua_getfield(L, -1, "cb");
	if (lua_type(L, -1) != LUA_TFUNCTION) {
		pr_err("No callback function found for acomp request\n");
		return 0;
	}

	lua_pushinteger(L, err);

	if (err == 0)
		lua_pushlstring(L, (const char *)obj->outbuf, obj->req->dlen);
	else
		lua_pushnil(L);

	lua_call(L, 2, 0);
	return 0;
}

static int luacrypto_acomp_req_lua_cb(lua_State *L, void *data, int err)
{
	luacrypto_acomp_req_t *obj = (luacrypto_acomp_req_t *)data;

	obj->busy = false;

	if (obj->refs == LUA_NOREF)
		return 0;
	
	/* Push the helper function and its arguments */
	lua_pushcfunction(L, luacrypto_acomp_req_call_cb);
	lua_pushlightuserdata(L, obj);
	lua_pushinteger(L, err);

	/* Call the helper via pcall to protect against errors */
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) {
		pr_err("Lua callback error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}

	/* Clean up the refs table */
	luaL_unref(L, LUA_REGISTRYINDEX, obj->refs);
	obj->refs = LUA_NOREF;

	return 0;
}

static void luacrypto_acomp_req_docall(void *data, int err)
{
	luacrypto_acomp_req_t *obj = (luacrypto_acomp_req_t *)data;
	int ret;

	lunatik_run(obj->runtime, luacrypto_acomp_req_lua_cb, ret, data, err);
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
	const char *in_buf, size_t in_len, unsigned int out_len)
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

	/* Table to hold all references */
	lua_newtable(L);
	
	lua_pushvalue(L, 4);
	lua_setfield(L, -2, "cb");
	
	lua_pushvalue(L, 2);
	lua_setfield(L, -2, "buf");
	
	lua_pushvalue(L, 1);
	lua_setfield(L, -2, "self");
	
	obj->refs = luaL_ref(L, LUA_REGISTRYINDEX);
	
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
	unsigned int out_len = lunatik_checkuint(L, 3);					\
	lunatik_checkbounds(L, 3, out_len, 1, UINT_MAX);					\
	luaL_checktype(L, 4, LUA_TFUNCTION);							\
												\
	lunatik_try(L, luacrypto_acomp_req_prepare, obj, L, in_buf, in_len, out_len);	\
	int ret = crypto_acomp_##name(obj->req);						\
	if (ret != -EINPROGRESS)								\
		luacrypto_acomp_req_docall(obj, ret);						\
	return 0;										\
}

/***
* Request object methods.
* These methods are available on request objects created by `ACOMPRESS:request()`.
* @type crypto_acomp_req
*/

/***
* Compresses data asynchronously using the ACOMPRESS transform.
* The callback is invoked when the operation completes (either synchronously or asynchronously).
* @function compress
* @tparam string data The data to compress.
* @tparam integer output_size The maximum size of the output buffer.
* @tparam function callback The callback function to invoke upon completion. It receives two arguments: `err` (integer error code, 0 on success) and `data` (string containing compressed data, or nil on error).
* @raise Error if the request object is busy, or if parameters are invalid.
*/
LUACRYPTO_ACOMP_REQ_OPERATION(compress)

/***
* Decompresses data asynchronously using the ACOMPRESS transform.
* The callback is invoked when the operation completes (either synchronously or asynchronously).
* @function decompress
* @tparam string data The compressed data to decompress.
* @tparam integer output_size The maximum size of the output buffer.
* @tparam function callback The callback function to invoke upon completion. It receives two arguments: `err` (integer error code, 0 on success) and `data` (string containing decompressed data, or nil on error).
* @raise Error if the request object is busy, or if parameters are invalid.
*/
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

/***
* ACOMPRESS object methods.
* These methods are available on ACOMPRESS TFM objects created by `crypto.acompress.new()`.
* @see new
* @type ACOMPRESS
*/

/***
* Creates a new asynchronous compression request object.
* Request objects are used to perform asynchronous compression and decompression operations.
* Multiple requests can be created from the same TFM and used concurrently.
* @function request
* @treturn crypto_acomp_req A new request object.
* @raise Error if request allocation fails.
*/
static int luacrypto_acompress_request(lua_State *L)
{
	struct crypto_acomp *tfm = luacrypto_acompress_check(L, 1);
	lunatik_object_t *object;
	luacrypto_acomp_req_t *req;

	object = lunatik_newobject(L, &luacrypto_acomp_req_class, sizeof(luacrypto_acomp_req_t));
	req = (luacrypto_acomp_req_t *)object->private;

	memset(req, 0, sizeof(luacrypto_acomp_req_t));
	req->runtime = lunatik_toruntime(L);
	lunatik_getobject(req->runtime);
	req->refs = LUA_NOREF;

	req->req = lunatik_checknull(L, luacrypto_acomp_request_alloc(tfm, L));

	return 1;
}

static const luaL_Reg luacrypto_acompress_mt[] = {
	{"request", luacrypto_acompress_request},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

/***
* Creates a new ACOMPRESS transform object for the specified algorithm.
* @function new
* @tparam string algorithm The name of the compression algorithm (e.g., "lz4", "deflate", "lzo").
* @treturn ACOMPRESS A new ACOMPRESS transform object.
* @raise Error if the algorithm is not found or allocation fails.
* @usage
*   local acomp = require("crypto.acompress")
*   local tfm = acomp.new("lz4")
*   local req = tfm:request()
* @within crypto_acompress
*/
LUACRYPTO_NEW(acompress, struct crypto_acomp, crypto_alloc_acomp, luacrypto_acompress_class, NULL);

static const luaL_Reg luacrypto_acompress_lib[] = {
	{"new", luacrypto_acompress_new},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_acompress_classes[] = {
	luacrypto_acompress_class,
	luacrypto_acomp_req_class,
	{NULL}
};

LUNATIK_NEWLIB_MULTICLASS(crypto_acompress, luacrypto_acompress_lib, luacrypto_acompress_classes, NULL);

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

