/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to asynchronous compression algorithms (acompress).
*
* Transform objects are created by `crypto.acompress()`; requests created
* from them perform asynchronous compression and decompression.
* @classmod crypto_acompress
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/acompress.h>
#include <linux/err.h>
#include <linux/slab.h>
#include <linux/limits.h>
#include <linux/scatterlist.h>

#include "luacrypto.h"

LUNATIK_PRIVATECHECKER(luacrypto_acompress_check, struct crypto_acomp *);

LUACRYPTO_RELEASER(acompress, struct crypto_acomp, crypto_free_acomp);

typedef struct luacrypto_acompress_req_s {
	struct acomp_req *req;
	struct scatterlist sg_in;
	struct scatterlist sg_out;
	lunatik_object_t *runtime;
	u8 *outbuf;
	size_t outbuf_len;
	bool busy;
} luacrypto_acompress_req_t;

LUNATIK_PRIVATECHECKER(luacrypto_acompress_req_check, luacrypto_acompress_req_t *);

static void luacrypto_acompress_req_release(void *private)
{
	luacrypto_acompress_req_t *obj = (luacrypto_acompress_req_t *)private;

	if (obj->runtime) {
		lua_State *L = lunatik_getstate(obj->runtime);

		if (L)
			lunatik_unregister(L, obj);

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

/*
 * Completes an operation on the given Lua state: pops the callback out of the
 * anchor table, releases the anchors and invokes it protected with
 * (err | nil, output | nil), where err is the errno name (e.g. "EINVAL").
 * The callback may submit new operations, but not on this very request when
 * completion is synchronous (inline): the object's non-recursive monitor
 * lock is still held by the submitting method.
 */
static void luacrypto_acompress_req_complete(lua_State *L, luacrypto_acompress_req_t *obj, int err)
{
	int n;

	if (lunatik_getregistry(L, obj) != LUA_TTABLE) {	/* anchors */
		pr_err("no anchor table found for acomp request\n");
		lua_pop(L, 1);
		return;
	}

	lua_getfield(L, -1, "cb");	/* anchors, cb */
	for (n = 1; n <= 2; n++) {	/* drop anchors so cb may submit again */
		lua_pushnil(L);
		lua_rawseti(L, -3, n);
	}
	lua_pushnil(L);
	lua_setfield(L, -3, "cb");
	lua_remove(L, -2);		/* cb */
	obj->busy = false;

	if (lua_type(L, -1) != LUA_TFUNCTION) {
		pr_err("no callback function found for acomp request\n");
		lua_pop(L, 1);
		return;
	}

	if (err == 0) {
		lua_pushnil(L);
		lua_pushlstring(L, (const char *)obj->outbuf, obj->req->dlen);
	} else {
		lunatik_pusherrname(L, err);
		lua_pushnil(L);
	}

	if (lua_pcall(L, 2, 0, 0) != LUA_OK) {	/* cb(err, output) */
		pr_err("callback error: %s\n", lua_tostring(L, -1));
		lua_pop(L, 1);
	}
}

static int luacrypto_acompress_req_handler(lua_State *L, luacrypto_acompress_req_t *obj, int err)
{
	luacrypto_acompress_req_complete(L, obj, err);
	return 0;
}

/*
 * Crypto API completion callback. Only reached on asynchronous completion
 * (submission returned -EINPROGRESS or -EBUSY), thus never while the
 * submitter still holds the runtime lock: lunatik_run() is deadlock-free here.
 */
static void luacrypto_acompress_req_docall(void *data, int err)
{
	luacrypto_acompress_req_t *obj = (luacrypto_acompress_req_t *)data;
	int ret;

	lunatik_run(obj->runtime, luacrypto_acompress_req_handler, ret, obj, err);
	(void)ret;
}

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 3, 0)
/* Before 6.3, crypto_completion_t received the async request, not its data. */
static void luacrypto_acompress_req_docall_compat(struct crypto_async_request *areq, int err)
{
	luacrypto_acompress_req_docall(areq->data, err);
}
#define LUACRYPTO_ACOMPRESS_CALLBACK	luacrypto_acompress_req_docall_compat
#else
#define LUACRYPTO_ACOMPRESS_CALLBACK	luacrypto_acompress_req_docall
#endif

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
#define luacrypto_acompress_request_alloc(tfm, L) ({	\
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));	\
	acomp_request_alloc(tfm, gfp);			\
})
#else
#define luacrypto_acompress_request_alloc(tfm, L)	acomp_request_alloc(tfm)
#endif

static int luacrypto_acompress_req_prepare(luacrypto_acompress_req_t *obj, lua_State *L,
	const char *in_buf, size_t in_len, unsigned int out_len)
{
	if (obj->outbuf_len < out_len) {
		u8 *outbuf = lunatik_checkalloc(L, out_len);
		lunatik_free(obj->outbuf);
		obj->outbuf = outbuf;
		obj->outbuf_len = out_len;
	}

	sg_init_one(&obj->sg_in, in_buf, in_len);
	sg_init_one(&obj->sg_out, obj->outbuf, out_len);

	acomp_request_set_params(obj->req, &obj->sg_in, &obj->sg_out, in_len, out_len);
	acomp_request_set_callback(obj->req,
		lunatik_gfp(lunatik_toruntime(L)) == GFP_KERNEL ?
			CRYPTO_TFM_REQ_MAY_BACKLOG | CRYPTO_TFM_REQ_MAY_SLEEP :
			CRYPTO_TFM_REQ_MAY_BACKLOG,
		LUACRYPTO_ACOMPRESS_CALLBACK, obj);
	return 0;
}

/*
 * Anchors the request userdata, the input string and the callback in the
 * preallocated table keyed by `obj`, so they outlive the submitting call
 * while the operation is in flight.
 */
static void luacrypto_acompress_req_anchor(lua_State *L, luacrypto_acompress_req_t *obj,
	int self_ix, int data_ix, int cb_ix)
{
	lunatik_getregistry(L, obj);	/* anchors */
	lua_pushvalue(L, data_ix);
	lua_rawseti(L, -2, 1);
	lua_pushvalue(L, self_ix);
	lua_rawseti(L, -2, 2);
	lua_pushvalue(L, cb_ix);
	lua_setfield(L, -2, "cb");
	lua_pop(L, 1);

	obj->busy = true;
}

#define LUACRYPTO_ACOMPRESS_REQ_OPERATION(name)							\
static int luacrypto_acompress_req_##name(lua_State *L)						\
{												\
	luacrypto_acompress_req_t *obj = luacrypto_acompress_req_check(L, 1);			\
	if (obj->busy)										\
		return luaL_error(L, "request object is busy");					\
												\
	size_t in_len;										\
	const char *in_buf = luaL_checklstring(L, 2, &in_len);					\
	lunatik_checkbounds(L, 2, in_len, 1, UINT_MAX);						\
	unsigned int out_len = (unsigned int)lunatik_checkinteger(L, 3, 1, UINT_MAX);		\
	luaL_checktype(L, 4, LUA_TFUNCTION);							\
												\
	lunatik_try(L, luacrypto_acompress_req_prepare, obj, L, in_buf, in_len, out_len);	\
	luacrypto_acompress_req_anchor(L, obj, 1, 2, 4);					\
	int ret = crypto_acomp_##name(obj->req);						\
	if (ret != -EINPROGRESS && ret != -EBUSY)						\
		luacrypto_acompress_req_complete(L, obj, ret);					\
	return 0;										\
}

/***
* Request object methods.
* These methods are available on request objects created by `ACOMPRESS:request()`.
* @type crypto_acompress_req
*/

/***
* Compresses data asynchronously.
* The callback is invoked when the operation completes (either synchronously or asynchronously).
* @function compress
* @tparam string data The data to compress.
* @tparam integer output_size The maximum size of the output buffer.
* @tparam function callback Receives `err` (errno name string, or nil on success) and `data` (compressed data, or nil on error).
* @raise Error if the request object is busy, or if parameters are invalid.
*/
LUACRYPTO_ACOMPRESS_REQ_OPERATION(compress)

/***
* Decompresses data asynchronously.
* The callback is invoked when the operation completes (either synchronously or asynchronously).
* @function decompress
* @tparam string data The compressed data to decompress.
* @tparam integer output_size The maximum size of the output buffer.
* @tparam function callback Receives `err` (errno name string, or nil on success) and `data` (decompressed data, or nil on error).
* @raise Error if the request object is busy, or if parameters are invalid.
*/
LUACRYPTO_ACOMPRESS_REQ_OPERATION(decompress)

/***
* Checks if the request object is currently busy with an asynchronous operation.
* @function busy
* @treturn boolean True if the request is busy, false otherwise.
*/
static int luacrypto_acompress_req_busy(lua_State *L)
{
	luacrypto_acompress_req_t *obj = luacrypto_acompress_req_check(L, 1);
	lua_pushboolean(L, obj->busy);
	return 1;
}

static const luaL_Reg luacrypto_acompress_req_mt[] = {
	{"compress", luacrypto_acompress_req_compress},
	{"decompress", luacrypto_acompress_req_decompress},
	{"busy", luacrypto_acompress_req_busy},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_acompress_req_class = {
	.name = "crypto_acompress_req",
	.methods = luacrypto_acompress_req_mt,
	.release = luacrypto_acompress_req_release,
	.opt = LUNATIK_OPT_MONITOR,
};

/***
* ACOMPRESS object methods.
* These methods are available on ACOMPRESS transform objects created by `crypto.acompress()`.
* @see new
* @type ACOMPRESS
*/

/***
* Creates a new asynchronous compression request object.
* Multiple requests can be created from the same TFM and used concurrently.
* @function request
* @treturn crypto_acompress_req A new request object.
* @raise Error if request allocation fails.
*/
static int luacrypto_acompress_request(lua_State *L)
{
	struct crypto_acomp *tfm = luacrypto_acompress_check(L, 1);
	lunatik_object_t *object;
	luacrypto_acompress_req_t *req;

	object = lunatik_newobject(L, &luacrypto_acompress_req_class,
		sizeof(luacrypto_acompress_req_t), LUNATIK_OPT_NONE);
	req = (luacrypto_acompress_req_t *)object->private;

	memset(req, 0, sizeof(luacrypto_acompress_req_t));
	req->runtime = lunatik_toruntime(L);
	lunatik_getobject(req->runtime);

	req->req = lunatik_checknull(L, luacrypto_acompress_request_alloc(tfm, L));

	/* Preallocate the anchor table so submissions never allocate it. */
	lua_createtable(L, 2, 1);
	lunatik_register(L, -1, req);
	lua_pop(L, 1);

	return 1;
}

static const luaL_Reg luacrypto_acompress_mt[] = {
	{"request", luacrypto_acompress_request},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_acompress_class = {
	.name = "crypto_acompress",
	.methods = luacrypto_acompress_mt,
	.release = luacrypto_acompress_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

/***
* Creates a new ACOMPRESS transform object for the specified algorithm.
* @function new
* @tparam string algname The name of the compression algorithm (e.g., "lz4", "deflate", "lzo").
* @treturn crypto_acompress A new ACOMPRESS transform object.
* @raise Error if the algorithm is not found or allocation fails.
* @usage
*   local acompress = require("crypto").acompress
*   local tfm = acompress("lz4")
*   local req = tfm:request()
*/
LUACRYPTO_NEW(acompress, struct crypto_acomp, crypto_alloc_acomp, luacrypto_acompress_class);
