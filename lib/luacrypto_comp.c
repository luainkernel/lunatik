/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to compression algorithms, over the kernel's acomp API.
* An asynchronous implementation, such as a hardware engine's, is served: `compress` and
* `decompress` wait for its result. The wait sleeps, and a stop does not end it: a thread whose call
* waits on an engine that never completes cannot be stopped.
* On 6.14 and earlier the kernel runs a software implementation, `lz4` and `deflate` among them,
* through a buffer of 128 KiB: an input past it raises "EINVAL", and so does an output past it.
* @classmod crypto_comp
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/acompress.h>
#include <linux/crypto.h>
#include <linux/err.h>
#include <linux/limits.h>
#include <linux/overflow.h>
#include <linux/scatterlist.h>

#include "luacrypto.h"

typedef int (*luacrypto_comp_op_t)(struct acomp_req *request);

LUACRYPTO_CHECKER(comp, struct crypto_acomp);

static void luacrypto_comp_release(void *private)
{
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)private;

	if (ctx->request) /* acomp_request_free reads the request's transform on 6.14 and earlier */
		acomp_request_free(ctx->request);
	if (ctx->tfm)
		crypto_free_acomp(ctx->tfm);
}

static int luacrypto_comp_operation(lua_State *L, luacrypto_comp_op_t op)
{
	luacrypto_ctx_t *ctx = luacrypto_comp_checkctx(L, 1);
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	lunatik_checkbounds(L, 2, datalen, 1, UINT_MAX);
	unsigned int max_len = (unsigned int)lunatik_checkinteger(L, 3, 1, UINT_MAX);
	struct acomp_req *request = (struct acomp_req *)ctx->request;
	struct scatterlist src, dst;
	DECLARE_CRYPTO_WAIT(wait);

	/* output, the NUL lunatik_pushexternalstring writes, then a copy of data: a scatterlist maps linear memory */
	char *buffer = luacrypto_newbuffer(L, size_add(size_add(max_len, 1), datalen));
	char *input = buffer + max_len + 1;

	memcpy(input, data, datalen);
	sg_init_one(&src, input, datalen);
	sg_init_one(&dst, buffer, max_len);
	acomp_request_set_params(request, &src, &dst, datalen, max_len);
	acomp_request_set_callback(request, CRYPTO_TFM_REQ_MAY_BACKLOG, crypto_req_done, &wait);

	int ret = crypto_wait_req(op(request), &wait);
	return luacrypto_pushbuffer(L, buffer, ret, request->dlen);
}

#define LUACRYPTO_COMP_OPERATION(op)					\
static int luacrypto_comp_##op(lua_State *L)				\
{									\
	return luacrypto_comp_operation(L, crypto_acomp_##op);		\
}

/***
* Compresses data.
* @function compress
* @tparam string data input data
* @tparam integer max_len maximum size of compressed output
* @treturn string compressed data
* @raise on compression failure, "not enough memory" when one kmalloc block cannot be allocated for
*   the output and a copy of the input, always past `KMALLOC_MAX_SIZE`
*/
LUACRYPTO_COMP_OPERATION(compress)

/***
* Decompresses data.
* @function decompress
* @tparam string data compressed input
* @tparam integer max_len maximum size of decompressed output
* @treturn string decompressed data
* @raise on decompression failure, "not enough memory" when one kmalloc block cannot be allocated
*   for the output and a copy of the input, always past `KMALLOC_MAX_SIZE`
*/
LUACRYPTO_COMP_OPERATION(decompress)

/***
* Returns the driver-independent name of the algorithm the transform was allocated with.
* @function algname
* @treturn string
*/
static int luacrypto_comp_algname(lua_State *L)
{
	struct crypto_acomp *tfm = luacrypto_comp_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_acomp_tfm(tfm)));
	return 1;
}

/***
* Releases the transform.
* A to-be-closed variable holding the object releases it the same way. Calling it again does
* nothing, and every other method raises "closed object" afterwards.
* @function close
* @treturn nil
*/
static const luaL_Reg luacrypto_comp_mt[] = {
	{"algname", luacrypto_comp_algname},
	{"compress", luacrypto_comp_compress},
	{"decompress", luacrypto_comp_decompress},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_comp_class = {
	.name = "crypto.comp",
	.methods = luacrypto_comp_mt,
	.release = luacrypto_comp_release,
	.opt = LUNATIK_OPT_MONITOR,
	.owner = THIS_MODULE,
};

int luacrypto_comp_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_comp_class, sizeof(luacrypto_ctx_t),
		LUNATIK_OPT_NONE);
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)object->private;
	struct crypto_acomp *tfm = crypto_alloc_acomp(algname, 0, 0);

	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));

	ctx->tfm = tfm;
	luacrypto_initctx(L, ctx, acomp_request_alloc(tfm), 0);
	return 1;
}

