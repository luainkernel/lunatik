/*
* SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface to the Linux Kernel Crypto API for asynchronous
* compression algorithms (acompress).
*
* This module provides a `new` function to create ACOMPRESS transform objects,
* which can then be used for compression and decompression.
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

typedef struct luacrypto_acomp_req_s {
	struct crypto_acomp *tfm;
	struct acomp_req *req;
	struct scatterlist *sg_in;
	struct scatterlist *sg_out;
	int cb_ref;
	lua_State *L;
	u8 *outbuf_data;
	size_t outbuf_len;
} luacrypto_acomp_req_t;

LUNATIK_PRIVATECHECKER(luacrypto_acompress_check, luacrypto_acomp_req_t *);

static inline void luacrypto_acompress_release(void *private)
{
	luacrypto_acomp_req_t *obj = (luacrypto_acomp_req_t *)private;

	if (obj->cb_ref)
		luaL_unref(obj->L, LUA_REGISTRYINDEX, obj->cb_ref);

	lunatik_free(obj->sg_in);
	lunatik_free(obj->sg_out);
	lunatik_free(obj->outbuf_data);
	acomp_request_free(obj->req);
	crypto_free_acomp(obj->tfm);
}

/***
* ACOMPRESS Object methods.
* These methods are available on ACOMPRESS objects created by `acompress.new()`.
* @see new
* @type ACOMPRESS
*/

static void luacrypto_acompress_lua_callback(void *data, int err)
{
	luacrypto_acomp_req_t *obj = data;

	lua_rawgeti(obj->L, LUA_REGISTRYINDEX, obj->cb_ref);
	lua_pushinteger(obj->L, err);

	if (err == 0)
		lua_pushlstring(obj->L, (const char *)obj->outbuf_data, obj->req->dlen);
	else
		lua_pushnil(obj->L);

	lua_call(obj->L, 2, 0);
	luaL_unref(obj->L, LUA_REGISTRYINDEX, obj->cb_ref);
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
#define luacrypto_acompress_request_alloc(tfm, L) ({	\
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));	\
	acomp_request_alloc(tfm, gfp);			\
})
#else
#define luacrypto_acompress_request_alloc(tfm, L)	acomp_request_alloc(tfm)
#endif

static inline int luacrypto_acompress_prepare(luacrypto_acomp_req_t *obj, lua_State *L, const char *in_buf,
		size_t in_len, unsigned int out_len, int cb_ref)
{
	obj->req = luacrypto_acompress_request_alloc(obj->tfm, L);
	if (!obj->req)
		luaL_error(L, "failed to allocate request");

	obj->outbuf_data = lunatik_checkalloc(L, out_len);
	obj->outbuf_len = out_len;

	obj->sg_in = lunatik_checkalloc(L, sizeof(struct scatterlist));
	sg_init_one(obj->sg_in, in_buf, in_len);
	obj->sg_out = lunatik_checkalloc(L, sizeof(struct scatterlist));
	sg_init_one(obj->sg_out, obj->outbuf_data, out_len);

	acomp_request_set_params(obj->req, obj->sg_in, obj->sg_out, in_len, out_len);

	obj->cb_ref = cb_ref;
	obj->L = L;

	acomp_request_set_callback(obj->req, 0, luacrypto_acompress_lua_callback, obj);

	return 0;
}

#define LUACRYPTO_ACOMPRESS_OPERATION(name)							\
static int luacrypto_acompress_##name(lua_State *L)						\
{												\
	luacrypto_acomp_req_t *obj = luacrypto_acompress_check(L, 1);				\
	size_t in_len;										\
	const char *in_buf = luaL_checklstring(L, 2, &in_len);					\
	lunatik_checkbounds(L, 2, in_len, 1, UINT_MAX);						\
	unsigned int out_len = lunatik_checkuint(L, 3);						\
	luaL_checktype(L, 4, LUA_TFUNCTION);							\
	lua_pushvalue(L, 4);									\
	int cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);						\
	lunatik_try(L, luacrypto_acompress_prepare, obj, L, in_buf, in_len, out_len, cb_ref);	\
	int ret = crypto_acomp_##name(obj->req);						\
	if (ret != -EINPROGRESS)								\
		luacrypto_acompress_lua_callback(obj, ret);					\
	return 0;										\
}

/***
* Submits a compress request.
* @function compress
* @tparam string input
* @tparam integer output_len
* @tparam function callback Receives (err, output)
* @usage
*   req:compress(input, #input + 64, function(err, output) ... end)
*/
LUACRYPTO_ACOMPRESS_OPERATION(compress)

/***
* Submits a decompress request.
* @function decompress
* @tparam string input
* @tparam integer output_len
* @tparam function callback Receives (err, output)
* @usage
*   req:decompress(input, 4096, function(err, output) ... end)
*/
LUACRYPTO_ACOMPRESS_OPERATION(decompress)

static const luaL_Reg luacrypto_acompress_mt[] = {
	{"compress", luacrypto_acompress_compress},
	{"decompress", luacrypto_acompress_decompress},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{NULL, NULL}
};

static const lunatik_class_t luacrypto_acompress_class = {
	.name = "crypto_acompress",
	.methods = luacrypto_acompress_mt,
	.release = luacrypto_acompress_release,
	.sleep = true,
};

/***
* Allocates a new acompress request object.
* @function new
* @tparam string algname The name of the compression algorithm (e.g., "lz4", "deflate").
* @treturn acomp The new ACOMPRESS request object.
* @raise Error if the TFM object cannot be allocated/initialized.
* @usage
*   local req = require("crypto.acompress").new("lz4")
* @within acompress
*/
static int luacrypto_acompress_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);

	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_acompress_class, sizeof(luacrypto_acomp_req_t));
	luacrypto_acomp_req_t *req = (luacrypto_acomp_req_t *)object->private;

	memset(req, 0, sizeof(*req));

	req->tfm = crypto_alloc_acomp(algname, 0, 0);
	if (IS_ERR(req->tfm)) {
		long err = PTR_ERR(req->tfm);
		return luaL_error(L, "Failed to allocate acomp transform for %s (err %ld)", algname, err);
	}

	return 1;
}

static const luaL_Reg luacrypto_acompress_lib[] = {
	{"new", luacrypto_acompress_new},
	{NULL, NULL}
};

LUNATIK_NEWLIB(crypto_acompress, luacrypto_acompress_lib, &luacrypto_acompress_class, NULL);

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

