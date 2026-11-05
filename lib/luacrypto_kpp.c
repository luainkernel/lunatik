/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Lua interface to ECDH key agreement.
* An object holds one private key, set at creation and held by the kernel's transform alone: the
* binding keeps no copy of it, and the transform is freed zeroed. Keys and secrets are the kernel's
* big-endian bytes, each scalar or coordinate of the curve's size, 32 bytes for P-256: a public key
* is `x || y`, the SEC1 uncompressed point without its leading `0x04`, and a shared secret is the x
* coordinate of the product, the raw ECDH output a KDF such as `crypto.hkdf` takes. The shared
* secret is a Lua string, which Lua does not zero when it collects it, nor the private key a script
* passes to the constructor: a key the kernel generates never is one.
* @classmod crypto_kpp
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <crypto/ecdh.h>
#include <crypto/kpp.h>
#include <linux/err.h>
#include <linux/scatterlist.h>

#include "luacrypto.h"

#if IS_REACHABLE(CONFIG_CRYPTO_ECDH)

typedef int (*luacrypto_kpp_op_t)(struct kpp_request *request);

LUACRYPTO_CHECKER(kpp, struct crypto_kpp);

LUACRYPTO_RELEASERCTX(kpp, struct crypto_kpp, crypto_free_kpp);

static int luacrypto_kpp_compute(luacrypto_ctx_t *ctx, luacrypto_kpp_op_t op, struct scatterlist *src,
	unsigned int srclen, char *output, unsigned int outputlen)
{
	struct kpp_request *request = (struct kpp_request *)ctx->request;
	struct scatterlist dst;
	DECLARE_CRYPTO_WAIT(wait);

	sg_init_one(&dst, output, outputlen);
	kpp_request_set_input(request, src, srclen);
	kpp_request_set_output(request, &dst, outputlen);
	/* hisi_hpre and atmel-ecc answer -EINPROGRESS without flagging CRYPTO_ALG_ASYNC */
	kpp_request_set_callback(request, CRYPTO_TFM_REQ_MAY_BACKLOG, crypto_req_done, &wait);
	return crypto_wait_req(op(request), &wait);
}

/***
* Returns the public key, twice the curve's size: 64 bytes for P-256.
* @function publickey
* @treturn string `x || y`
* @raise the errno of a kernel failure, "not enough memory" when the binding cannot allocate the key
*/
static int luacrypto_kpp_publickey(lua_State *L)
{
	luacrypto_ctx_t *ctx = luacrypto_kpp_checkctx(L, 1);
	unsigned int len = crypto_kpp_maxsize(ctx->tfm);
	char *buffer = luacrypto_newbuffer(L, len + 1); /* the NUL lunatik_pushexternalstring writes */

	int ret = luacrypto_kpp_compute(ctx, crypto_kpp_generate_public_key, NULL, 0, buffer, len);
	return luacrypto_pushbuffer(L, buffer, ret, len, false);
}

/***
* Agrees a secret with a peer's public key.
* A key the curve refuses is the peer's, not the script's mistake, so it is an outcome and not an
* error, and no part of a secret is returned for it.
* @function sharedsecret
* @tparam string peer the peer's public key, `x || y`, as `publickey` returns it
* @treturn string the shared secret, of the curve's size, or nil and "EINVAL" for a key of another
*   length than `publickey`'s, a point off the curve or the point at infinity
* @raise the errno of a kernel failure, "not enough memory" when the binding cannot allocate the
*   secret
*/
static int luacrypto_kpp_sharedsecret(lua_State *L)
{
	luacrypto_ctx_t *ctx = luacrypto_kpp_checkctx(L, 1);
	size_t peerlen;
	const char *peer = luaL_checklstring(L, 2, &peerlen);
	unsigned int publiclen = crypto_kpp_maxsize(ctx->tfm);
	unsigned int len = publiclen / 2; /* the x coordinate: ECDH writes no dst_len back */
	struct scatterlist src;

	if (peerlen != publiclen) /* the copy below reads this many bytes of it */
		return lunatik_pushfail(L, -EINVAL);

	/* room for the whole point, where the NUL lunatik_pushexternalstring writes lands, then the peer's key */
	char *buffer = luacrypto_newbuffer(L, 2 * publiclen);
	memcpy(buffer + publiclen, peer, publiclen); /* a scatterlist maps linear memory */
	sg_init_one(&src, buffer + publiclen, publiclen);

	/* hisi_hpre refuses an output shorter than the point and writes x first */
	int ret = luacrypto_kpp_compute(ctx, crypto_kpp_compute_shared_secret, &src, publiclen, buffer, publiclen);
	return luacrypto_pushbuffer(L, buffer, ret, len, ret == -EINVAL);
}

/***
* Returns the driver-independent name of the algorithm the transform was allocated with.
* @function algname
* @treturn string
*/
static int luacrypto_kpp_algname(lua_State *L)
{
	struct crypto_kpp *tfm = luacrypto_kpp_check(L, 1);
	lua_pushstring(L, crypto_tfm_alg_name(crypto_kpp_tfm(tfm)));
	return 1;
}

/***
* Releases the transform and the private key it holds.
* A to-be-closed variable holding the object releases it the same way. Calling it again does
* nothing, and every other method raises "closed object" afterwards.
* @function close
* @treturn nil
*/
static const luaL_Reg luacrypto_kpp_mt[] = {
	{"algname", luacrypto_kpp_algname},
	{"publickey", luacrypto_kpp_publickey},
	{"sharedsecret", luacrypto_kpp_sharedsecret},
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"close", lunatik_closeobject},
	{NULL, NULL}
};

const lunatik_class_t luacrypto_kpp_class = {
	.name = "crypto.kpp",
	.methods = luacrypto_kpp_mt,
	.release = luacrypto_kpp_release,
	.opt = LUNATIK_OPT_MONITOR,
	.owner = THIS_MODULE,
};

/* packed as the kernel's ECDH users pack it; an empty key makes the transform generate one */
static void luacrypto_kpp_setsecret(lua_State *L, struct crypto_kpp *tfm, const char *key, size_t keylen)
{
	struct ecdh params = {.key = (char *)key, .key_size = keylen};
	unsigned int len = crypto_ecdh_key_len(&params);
	char *secret = luacrypto_newbuffer(L, len);

	crypto_ecdh_encode_key(secret, len, &params); /* fails only for a NULL buffer or another len */
	int ret = crypto_kpp_set_secret(tfm, secret, len);
	kfree_sensitive(secret);
	if (ret < 0)
		lunatik_throw(L, ret);
	/* curve25519 takes a packed key the size of its own as raw bytes; key_size truncates */
	if (key != NULL && keylen * 2 != crypto_kpp_maxsize(tfm))
		lunatik_throw(L, -EINVAL);
}

int luacrypto_kpp_new(lua_State *L)
{
	const char *algname = luaL_checkstring(L, 1);
	size_t keylen;
	const char *key = luaL_optlstring(L, 2, NULL, &keylen);
	lunatik_object_t *object = lunatik_newobject(L, &luacrypto_kpp_class, sizeof(luacrypto_ctx_t),
		LUNATIK_OPT_NONE);
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)object->private;
	struct crypto_kpp *tfm = crypto_alloc_kpp(algname, 0, 0);

	if (IS_ERR(tfm))
		lunatik_throw(L, PTR_ERR(tfm));

	ctx->tfm = tfm;
	luacrypto_initctx(L, ctx, kpp_request_alloc(tfm, lunatik_gfp(lunatik_toruntime(L))), 0);
	luacrypto_kpp_setsecret(L, tfm, key, keylen);
	return 1;
}

#endif

