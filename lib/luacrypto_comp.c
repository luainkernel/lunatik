/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to compression algorithms, served by the asynchronous compression API on every
* supported kernel.
* Each call waits for the operation to finish, a hardware engine included. The wait sleeps, so
* the class remains reserved to process context, and a stop does not end it: a thread whose call
* waits for an engine that never finishes cannot be stopped.
* Up to 6.14, an algorithm the kernel serves through scomp, `lz4` and `deflate` among them,
* refuses an input past 128 KiB with `EINVAL` and fails an output past 128 KiB whatever `max_len`
* says, so `lz4` raises `EINVAL` on incompressible data of 131072 bytes.
* @classmod crypto_comp
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/acompress.h>
#include <linux/crypto.h>
#include <linux/err.h>
#include <linux/limits.h>
#include <linux/scatterlist.h>
#include <linux/slab.h>

#include "luacrypto.h"

LUACRYPTO_CHECKER(comp, struct crypto_acomp)

static void luacrypto_comp_release(void *private)
{
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)private;

	if (ctx == NULL)
		return;
	if (ctx->request)
		acomp_request_free((struct acomp_req *)ctx->request);
	if (ctx->tfm)
		crypto_free_acomp((struct crypto_acomp *)ctx->tfm);
}

static int luacrypto_comp_operate(lua_State *L, int (*op)(struct acomp_req *))
{
	luacrypto_ctx_t *ctx = luacrypto_comp_checkctx(L, 1);
	struct acomp_req *req = (struct acomp_req *)ctx->request;
	size_t datalen;
	const char *data = luaL_checklstring(L, 2, &datalen);
	lunatik_checkbounds(L, 2, datalen, 1, UINT_MAX);
	unsigned int max_len = (unsigned int)lunatik_checkinteger(L, 3, 1, UINT_MAX);

	/* a byte past the output for the NUL, checked so max_len + 1 cannot wrap on 32 bits */
	size_t out_len = (size_t)max_len + 1;
	if (out_len == 0)
		lunatik_enomem(L);

	/* a scatterlist maps linear memory, and a Lua string may live in vmalloc */
	char *input = luacrypto_newbuffer(L, datalen);
	memcpy(input, data, datalen);

	gfp_t gfp = GFP_KERNEL | __GFP_NOWARN;
	char *output = kmalloc(out_len, gfp);
	if (output == NULL) {
		lunatik_free(input);
		lunatik_enomem(L);
	}

	struct scatterlist sg_in;
	struct scatterlist sg_out;
	sg_init_one(&sg_in, input, datalen);
	sg_init_one(&sg_out, output, max_len);
	acomp_request_set_params(req, &sg_in, &sg_out, datalen, max_len);

	DECLARE_CRYPTO_WAIT(wait);
	acomp_request_set_callback(req,
		CRYPTO_TFM_REQ_MAY_BACKLOG | CRYPTO_TFM_REQ_MAY_SLEEP,
		crypto_req_done, &wait);

	int ret = crypto_wait_req(op(req), &wait);
	lunatik_free(input);
	if (ret < 0) {
		lunatik_free(output);
		lunatik_throw(L, ret);
	}

	size_t dlen = req->dlen;
	/* krealloc keeps a block the size fits in, and Lua counts dlen only: the rest would escape the GC */
	char *result = kmalloc(dlen + 1, gfp);
	if (result) {
		memcpy(result, output, dlen);
		lunatik_free(output);
		output = result;
	}
	lunatik_pushexternalstring(L, output, dlen);
	return 1;
}

#define LUACRYPTO_COMP_OPERATION(name)							\
static int luacrypto_comp_##name(lua_State *L)						\
{											\
	return luacrypto_comp_operate(L, crypto_acomp_##name);				\
}

/***
* Compresses data.
* @function compress
* @tparam string data input data
* @tparam integer max_len maximum size of compressed output
* @treturn string compressed data
* @raise on compression failure, "not enough memory" when one kmalloc block cannot be allocated,
*   always past `KMALLOC_MAX_SIZE`
*/
LUACRYPTO_COMP_OPERATION(compress);

/***
* Decompresses data.
* @function decompress
* @tparam string data compressed input
* @tparam integer max_len maximum size of decompressed output
* @treturn string decompressed data
* @raise on decompression failure, "not enough memory" when one kmalloc block cannot be
*   allocated, always past `KMALLOC_MAX_SIZE`
*/
LUACRYPTO_COMP_OPERATION(decompress);

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
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_comp_class,
		sizeof(luacrypto_ctx_t), LUNATIK_OPT_NONE);
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)object->private;
	struct crypto_acomp *tfm = crypto_alloc_acomp(algname, 0, 0);

	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));
	ctx->tfm = tfm;
	luacrypto_initctx(L, ctx, acomp_request_alloc(tfm), 0);
	return 1;
}

