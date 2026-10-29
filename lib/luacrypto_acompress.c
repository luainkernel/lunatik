/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to asynchronous compression algorithms (acompress).
*
* Transform objects are created by `crypto.acompress()`; requests created
* from them compress and decompress, asynchronously when a callback is given
* and synchronously otherwise.
* @classmod crypto_acompress
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/acompress.h>
#include <linux/crypto.h>
#include <linux/limits.h>
#include <linux/scatterlist.h>
#include <linux/string.h>

#include "luacrypto.h"

typedef struct luacrypto_acompress_s {
	struct crypto_acomp *tfm;
	atomic_t requests;	/* a request's release runs from the GC, maybe inside a method holding this lock */
} luacrypto_acompress_t;

LUNATIK_PRIVATECHECKER(luacrypto_acompress_checkctx, luacrypto_acompress_t *,
	&luacrypto_acompress_class);

static inline struct crypto_acomp *luacrypto_acompress_check(lua_State *L, int ix)
{
	return luacrypto_acompress_checkctx(L, ix)->tfm;
}

static void luacrypto_acompress_release(void *private)
{
	luacrypto_acompress_t *acomp = (luacrypto_acompress_t *)private;

	if (acomp->tfm)
		crypto_free_acomp(acomp->tfm);
}

#define LUACRYPTO_ACOMPRESS_ERR_BUSY	"request object is busy"
#define LUACRYPTO_ACOMPRESS_ERR_REQUESTS	"transform has live requests"

typedef struct luacrypto_acompress_req_s {
	struct acomp_req *req;
	struct scatterlist sg_in;
	struct scatterlist sg_out;
	lunatik_object_t *object;	/* held while an operation is in flight */
	lunatik_object_t *tfm;
	lunatik_object_t *runtime;
	lunatik_defer_t defer;	/* an atomic completion runs its work */
	u8 *inbuf;
	u8 *outbuf;
	size_t outbuf_len;
	int err;	/* the outcome the callback receives */
	bool busy;
} luacrypto_acompress_req_t;

LUNATIK_PRIVATECHECKER(luacrypto_acompress_req_check, luacrypto_acompress_req_t *,
	&luacrypto_acompress_req_class);

static void luacrypto_acompress_req_release(void *private)
{
	luacrypto_acompress_req_t *obj = (luacrypto_acompress_req_t *)private;

	if (obj->runtime) {
		lunatik_putobject(obj->runtime);
		obj->runtime = NULL;
	}

	if (obj->req) {
		acomp_request_free(obj->req);
		obj->req = NULL;
	}

	if (obj->tfm) {
		atomic_dec(&((luacrypto_acompress_t *)obj->tfm->private)->requests);
		lunatik_putobject(obj->tfm);
		obj->tfm = NULL;
	}

	if (obj->inbuf) {
		lunatik_free(obj->inbuf);
		obj->inbuf = NULL;
	}

	if (obj->outbuf) {
		lunatik_free(obj->outbuf);
		obj->outbuf = NULL;
	}
}

/* Drops the anchors, leaving the callback on the stack. */
static void luacrypto_acompress_req_unanchor(lua_State *L, luacrypto_acompress_req_t *obj)
{
	if (lunatik_getregistry(L, obj->object) != LUA_TTABLE)	/* anchors */
		luaL_error(L, "couldn't find anchor table for acomp request");

	lua_getfield(L, -1, "cb");	/* anchors, cb */
	lua_pushnil(L);
	lua_rawseti(L, -3, 1);	/* drop anchors so cb may submit again */
	lua_pushnil(L);
	lua_setfield(L, -3, "cb");
	lua_remove(L, -2);	/* cb */
	lunatik_unregister(L, obj->object);
}

typedef struct luacrypto_acompress_call_s {
	luacrypto_acompress_req_t *obj;
	bool called;
} luacrypto_acompress_call_t;

/*
 * Runs inside the protected call: lua_pushlstring allocates and may therefore
 * raise, which outside a pcall would panic the kernel.
 */
static int luacrypto_acompress_req_invoke(lua_State *L)
{
	luacrypto_acompress_call_t *call = (luacrypto_acompress_call_t *)lua_touserdata(L, 1);
	luacrypto_acompress_req_t *obj = call->obj;

	luacrypto_acompress_req_unanchor(L, obj);	/* cb */
	luaL_checktype(L, -1, LUA_TFUNCTION);
	if (obj->err == 0) {
		lua_pushnil(L);
		lua_pushlstring(L, (const char *)obj->outbuf, obj->req->dlen);
	}
	else {
		lunatik_pusherrname(L, obj->err);
		lua_pushnil(L);
	}
	smp_store_release(&obj->busy, false);	/* after the copy: close frees outbuf once busy reads false */
	call->called = true;
	lua_call(L, 2, 0);	/* cb(err, output) */
	return 0;
}

/*
 * Completes an operation on the given Lua state: frees the input copy, drops
 * the anchors and invokes the callback protected with (err | nil, output | nil),
 * where err is the errno name (e.g. "EINVAL"). The request is not read once the
 * callback may have run, since the callback, or a sharer, may close it.
 * The callback may submit a new operation, but not on this very request when
 * completion is synchronous (inline): the object's non-recursive monitor
 * lock is still held by the submitting method.
 */
static void luacrypto_acompress_req_complete(lua_State *L, luacrypto_acompress_req_t *obj, int err)
{
	obj->err = err;
	lunatik_free(obj->inbuf);
	obj->inbuf = NULL;
	luacrypto_acompress_call_t call = {.obj = obj, .called = false};

	if (lunatik_catch(L, luacrypto_acompress_req_invoke, &call, "acompress callback") != 0 && !call.called)
		obj->busy = false;
}

/* Delivers the outcome and drops the reference the submission took. */
static void luacrypto_acompress_req_finish(lua_State *L, luacrypto_acompress_req_t *obj, int err)
{
	lunatik_object_t *object = obj->object;

	luacrypto_acompress_req_complete(L, obj, err);
	lunatik_putobject(object);
}

static int luacrypto_acompress_req_handler(lua_State *L, luacrypto_acompress_req_t *obj, int err)
{
	luacrypto_acompress_req_finish(L, obj, err);
	return 0;
}

/*
 * Re-enters the runtime from process context. A runtime that is gone or whose
 * lock the submitting task holds is not entered: the request is only marked
 * idle, and its anchors die with the state.
 */
static void luacrypto_acompress_req_resume(luacrypto_acompress_req_t *obj)
{
	lunatik_object_t *runtime = obj->runtime;
	lunatik_object_t *object = obj->object;
	int ret;

	/* the call may free the request, and with it the last reference the request held */
	lunatik_getobject(runtime);
	lunatik_run(runtime, luacrypto_acompress_req_handler, ret, obj, obj->err);
	if (ret != 0) {
		obj->busy = false;
		lunatik_putobject(object);
	}
	lunatik_putobject(runtime);
}

static void luacrypto_acompress_req_deferred(struct work_struct *work)
{
	luacrypto_acompress_req_resume(container_of(lunatik_syncdefer(work),
		luacrypto_acompress_req_t, defer));
}

/* A driver may complete from softirq or hardirq, where lunatik_run's runtime
 * mutex may not be taken, so an atomic completion is handed to the workqueue. */
static void luacrypto_acompress_req_docall(void *data, int err)
{
	luacrypto_acompress_req_t *obj = (luacrypto_acompress_req_t *)data;

	obj->err = err;
	if (lunatik_isatomic())
		lunatik_defer(&obj->defer);
	else
		luacrypto_acompress_req_resume(obj);
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 15, 0)
#define luacrypto_acompress_request_alloc(tfm, L) ({	\
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));	\
	acomp_request_alloc(tfm, gfp);			\
})
#else
#define luacrypto_acompress_request_alloc(tfm, L)	acomp_request_alloc(tfm)
#endif

/*
 * Copies the input into kmalloc'd memory the scatterlist can map: a Lua
 * string may live in vmalloc. Runs while the submitter holds the runtime
 * lock, so the string cannot be collected underneath the copy. The output
 * buffer is kept across operations and grown when too small; the input copy
 * belongs to the request until the arm that submits frees it.
 */
static void luacrypto_acompress_req_prepare(luacrypto_acompress_req_t *obj, lua_State *L,
	const char *in_buf, size_t in_len, unsigned int out_len)
{
	if (obj->outbuf_len < out_len) {
		u8 *outbuf = luacrypto_newbuffer(L, out_len);
		lunatik_free(obj->outbuf);
		obj->outbuf = outbuf;
		obj->outbuf_len = out_len;
	}

	u8 *inbuf = luacrypto_newbuffer(L, in_len);
	memcpy(inbuf, in_buf, in_len);
	lunatik_free(obj->inbuf);
	obj->inbuf = inbuf;

	sg_init_one(&obj->sg_in, inbuf, in_len);
	sg_init_one(&obj->sg_out, obj->outbuf, out_len);

	acomp_request_set_params(obj->req, &obj->sg_in, &obj->sg_out, in_len, out_len);
}

/* Anchors the request and the callback under the request object while the
 * operation is in flight; the completion unregisters them. */
static void luacrypto_acompress_req_anchor(lua_State *L, luacrypto_acompress_req_t *obj,
	int self_ix, int cb_ix)
{
	lua_createtable(L, 2, 1);
	lua_pushvalue(L, self_ix);
	lua_rawseti(L, -2, 1);
	lua_pushvalue(L, cb_ix);
	lua_setfield(L, -2, "cb");
	lunatik_register(L, -1, obj->object);
	lua_pop(L, 1);

	obj->busy = true;
}

typedef int (*luacrypto_acompress_op_t)(struct acomp_req *req);

static int luacrypto_acompress_req_async(lua_State *L, luacrypto_acompress_req_t *obj,
	luacrypto_acompress_op_t op)
{
	acomp_request_set_callback(obj->req,
		lunatik_gfp(lunatik_toruntime(L)) == GFP_KERNEL ?
			CRYPTO_TFM_REQ_MAY_BACKLOG | CRYPTO_TFM_REQ_MAY_SLEEP :
			CRYPTO_TFM_REQ_MAY_BACKLOG,
		luacrypto_acompress_req_docall, obj);
	luacrypto_acompress_req_anchor(L, obj, 1, 4);
	lunatik_getobject(obj->object);	/* held until the operation completes */
	int ret = op(obj->req);
	if (ret != -EINPROGRESS && ret != -EBUSY)
		luacrypto_acompress_req_finish(L, obj, ret);
	return 0;
}

/* without a callback: crypto.comp's synchronous API, which 6.15 removed, served over acomp */
static int luacrypto_acompress_req_sync(lua_State *L, luacrypto_acompress_req_t *obj,
	luacrypto_acompress_op_t op)
{
	DECLARE_CRYPTO_WAIT(wait);
	int ret;

	acomp_request_set_callback(obj->req,
		CRYPTO_TFM_REQ_MAY_BACKLOG | CRYPTO_TFM_REQ_MAY_SLEEP,
		crypto_req_done, &wait);
	/* waits here, not on a callback: lunatik_run needs the runtime lock this script holds */
	ret = crypto_wait_req(op(obj->req), &wait);
	lunatik_free(obj->inbuf);
	obj->inbuf = NULL;

	if (ret < 0)
		lunatik_throw(L, ret);
	lua_pushlstring(L, (const char *)obj->outbuf, obj->req->dlen);
	return 1;
}

#define LUACRYPTO_ACOMPRESS_REQ_OPERATION(name)							\
static int luacrypto_acompress_req_##name(lua_State *L)						\
{												\
	luacrypto_acompress_req_t *obj = luacrypto_acompress_req_check(L, 1);			\
	if (obj->busy)										\
		return luaL_error(L, LUACRYPTO_ACOMPRESS_ERR_BUSY);				\
												\
	size_t in_len;										\
	const char *in_buf = luaL_checklstring(L, 2, &in_len);					\
	lunatik_checkbounds(L, 2, in_len, 1, UINT_MAX);						\
	unsigned int out_len = (unsigned int)lunatik_checkinteger(L, 3, 1, UINT_MAX);		\
	bool asynchronous = !lua_isnoneornil(L, 4);						\
	if (asynchronous)									\
		luaL_checktype(L, 4, LUA_TFUNCTION);						\
												\
	luacrypto_acompress_req_prepare(obj, L, in_buf, in_len, out_len);			\
	return asynchronous ?									\
		luacrypto_acompress_req_async(L, obj, crypto_acomp_##name) :			\
		luacrypto_acompress_req_sync(L, obj, crypto_acomp_##name);			\
}

/***
* Request object methods.
* These methods are available on request objects created by `ACOMPRESS:request()`.
* @type crypto_acompress_req
*/

/***
* Compresses data.
* Without a callback the operation is synchronous: it waits for the driver and returns the
* compressed data. With a callback it is asynchronous: it returns nothing, and the callback
* receives `err` (errno name string, or nil on success) and `data` (compressed data, or nil on
* error) when the operation completes. A callback does not run while the runtime that submitted
* it is busy, so that runtime must not wait for its own callback.
* @function compress
* @tparam string data The data to compress.
* @tparam integer max_len The maximum size of the output buffer.
* @tparam[opt] function callback Receives `err` and `data` when the operation completes.
* @treturn string|nil The compressed data, or nothing when a callback is given.
* @raise Error if the request object is busy, if parameters are invalid, or with the errno name
*   of a failed synchronous operation.
*/
LUACRYPTO_ACOMPRESS_REQ_OPERATION(compress)

/***
* Decompresses data.
* Without a callback the operation is synchronous: it waits for the driver and returns the
* decompressed data. With a callback it is asynchronous: it returns nothing, and the callback
* receives `err` (errno name string, or nil on success) and `data` (decompressed data, or nil on
* error) when the operation completes. A callback does not run while the runtime that submitted
* it is busy, so that runtime must not wait for its own callback.
* @function decompress
* @tparam string data The compressed data to decompress.
* @tparam integer max_len The maximum size of the output buffer.
* @tparam[opt] function callback Receives `err` and `data` when the operation completes.
* @treturn string|nil The decompressed data, or nothing when a callback is given.
* @raise Error if the request object is busy, if parameters are invalid, or with the errno name
*   of a failed synchronous operation.
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

/***
* Releases the request.
* A to-be-closed variable holding the object releases it the same way. Calling it again does
* nothing, and every other method raises "closed object" afterwards.
* @function close
* @treturn nil
* @raise Error if an operation is still in flight.
*/
static int luacrypto_acompress_req_close(lua_State *L)
{
	lunatik_checkirqs(L);
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luacrypto_acompress_req_class);
	luacrypto_acompress_req_t *obj;
	bool busy;

	/* close is outside the monitor, so this read of private takes its mutex itself */
	lunatik_lock(object);
	obj = (luacrypto_acompress_req_t *)object->private;
	busy = obj != NULL && smp_load_acquire(&obj->busy);
	lunatik_unlock(object);

	if (busy)
		return luaL_error(L, LUACRYPTO_ACOMPRESS_ERR_BUSY);

	lunatik_closeprivate(object);
	return 0;
}

static const luaL_Reg luacrypto_acompress_req_mt[] = {
	{"compress", luacrypto_acompress_req_compress},
	{"decompress", luacrypto_acompress_req_decompress},
	{"busy", luacrypto_acompress_req_busy},
	{"__gc", lunatik_deleteobject},
	{"__close", luacrypto_acompress_req_close},
	{"close", luacrypto_acompress_req_close},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_acompress_req_class = {
	.name = "crypto.acompress.request",
	.methods = luacrypto_acompress_req_mt,
	.release = luacrypto_acompress_req_release,
	.opt = LUNATIK_OPT_MONITOR,
	.owner = THIS_MODULE,
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
	luacrypto_acompress_t *acomp = luacrypto_acompress_checkctx(L, 1);
	lunatik_object_t *object;
	luacrypto_acompress_req_t *req;

	object = lunatik_newobject(L, &luacrypto_acompress_req_class,
		sizeof(luacrypto_acompress_req_t), LUNATIK_OPT_NONE);
	req = (luacrypto_acompress_req_t *)object->private;

	/* operations and acomp_request_free use the transform, which must outlive the request */
	req->tfm = lunatik_toobject(L, 1);
	lunatik_getobject(req->tfm);
	atomic_inc(&acomp->requests);	/* under the monitor's lock, which close reads it under */
	req->object = object;
	req->runtime = lunatik_toruntime(L);
	lunatik_getobject(req->runtime);
	lunatik_initdefer(&req->defer, luacrypto_acompress_req_deferred);

	req->req = lunatik_checknull(L, luacrypto_acompress_request_alloc(acomp->tfm, L));

	return 1;
}

/***
* Returns the driver-independent name of the algorithm the transform was allocated with.
* @function algname
* @treturn string
*/
static int luacrypto_acompress_algname(lua_State *L)
{
	struct crypto_acomp *tfm = luacrypto_acompress_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_acomp_tfm(tfm)));
	return 1;
}

/***
* Releases the transform.
* A to-be-closed variable holding the object releases it the same way. Calling it again does
* nothing, and every other method raises "closed object" afterwards.
* @function close
* @treturn nil
* @raise Error if the transform has live requests.
*/
static int luacrypto_acompress_close(lua_State *L)
{
	lunatik_checkirqs(L);
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luacrypto_acompress_class);
	luacrypto_acompress_t *acomp;

	lunatik_lock(object);
	acomp = (luacrypto_acompress_t *)object->private;
	if (acomp != NULL && atomic_read(&acomp->requests) > 0) {
		lunatik_unlock(object);
		return luaL_error(L, LUACRYPTO_ACOMPRESS_ERR_REQUESTS);
	}
	object->private = NULL;
	lunatik_unlock(object);

	if (acomp != NULL) {
		luacrypto_acompress_release(acomp);
		lunatik_free(acomp);
	}
	return 0;
}

static const luaL_Reg luacrypto_acompress_mt[] = {
	{"request", luacrypto_acompress_request},
	{"algname", luacrypto_acompress_algname},
	{"__gc", lunatik_deleteobject},
	{"__close", luacrypto_acompress_close},
	{"close", luacrypto_acompress_close},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_acompress_class = {
	.name = "crypto.acompress",
	.methods = luacrypto_acompress_mt,
	.release = luacrypto_acompress_release,
	.opt = LUNATIK_OPT_MONITOR,
	.owner = THIS_MODULE,
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
int luacrypto_acompress_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_acompress_class,
		sizeof(luacrypto_acompress_t), LUNATIK_OPT_NONE);
	luacrypto_acompress_t *acomp = (luacrypto_acompress_t *)object->private;
	struct crypto_acomp *tfm = crypto_alloc_acomp(algname, 0, 0);

	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));
	acomp->tfm = tfm;
	return 1;
}

