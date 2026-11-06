/*
* SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef _LUACRYPTO_H
#define _LUACRYPTO_H

#include <linux/err.h>
#include <lunatik.h>

#define LUACRYPTO_RELEASER(name, T, obj_free)			\
static void luacrypto_##name##_release(void *private)		\
{								\
	T *obj = (T *)private;					\
	if (obj)						\
		obj_free(obj);					\
}

#define LUACRYPTO_ALGNAME(name, tfm)				\
static int luacrypto_##name##_algname(lua_State *L)		\
{								\
	__auto_type private = luacrypto_##name##_check(L, 1);	\
	lua_pushstring(L, crypto_tfm_alg_name(tfm));		\
	return 1;						\
}

#define LUACRYPTO_DECLARE(name)					\
extern const lunatik_class_t luacrypto_##name##_class;		\
int luacrypto_##name##_new(lua_State *L)

/* Per-tfm fixed-size state (request, IV) allocated once at creation, so
 * encrypt/decrypt never allocates on the hot path. */
typedef struct luacrypto_ctx_s {
	void *tfm;
	void *request;
	u8 *iv;
} luacrypto_ctx_t;

/* checkctx returns the context; check returns ctx->tfm for tfm-only methods. */
#define LUACRYPTO_CHECKER(name, T, ...)							\
LUNATIK_PRIVATECHECKER(luacrypto_##name##_checkctx, luacrypto_ctx_t *, &luacrypto_##name##_class,	\
	##__VA_ARGS__)										\
static inline T *luacrypto_##name##_check(lua_State *L, int idx)				\
{											\
	return (T *)luacrypto_##name##_checkctx(L, idx)->tfm;				\
}

/* store the request and allocate the IV (NULL when the cipher has none),
 * failing if either could not be obtained */
static inline void luacrypto_initctx(lua_State *L, luacrypto_ctx_t *ctx,
	void *request, unsigned int ivsize)
{
	ctx->request = request;
	ctx->iv = ivsize != 0 ? (u8 *)lunatik_malloc(L, ivsize) : NULL;
	if (ctx->request == NULL || (ivsize != 0 && ctx->iv == NULL))
		lunatik_enomem(L);
}

#define LUACRYPTO_NEWCTX(name, T, alloc, class, ...)						\
int luacrypto_##name##_new(lua_State *L)							\
{												\
	__VA_ARGS__										\
	const char *algname = luaL_checkstring(L, 1);						\
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));						\
	lunatik_object_t *object = lunatik_newobject(L, &class,				\
		sizeof(luacrypto_ctx_t), LUNATIK_OPT_NONE);					\
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)object->private;				\
	T *tfm = alloc(algname, 0, CRYPTO_ALG_ASYNC);						\
	if (IS_ERR(tfm))									\
		lunatik_throw(L, PTR_ERR(tfm));							\
	ctx->tfm = tfm;										\
	luacrypto_initctx(L, ctx, name##_request_alloc(tfm, gfp),				\
		crypto_##name##_ivsize(tfm));							\
	return 1;										\
}

#define LUACRYPTO_RELEASERCTX(name, T, request_free, tfm_free)	\
static void luacrypto_##name##_release(void *private)		\
{								\
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)private;	\
	if (ctx == NULL)					\
		return;						\
	if (ctx->request) /* acomp_request_free reads the request's transform on 6.14 and earlier */	\
		request_free(ctx->request);			\
	lunatik_free(ctx->iv);					\
	if (ctx->tfm)						\
		tfm_free((T *)ctx->tfm);			\
}

static inline u8 *luacrypto_checkiv(lua_State *L, int idx, u8 *iv, size_t expected)
{
	size_t iv_len;
	const char *str = luaL_checklstring(L, idx, &iv_len);
	if (iv_len != expected)
		lunatik_throw(L, -EINVAL);
	if (iv_len == 0)
		return NULL;

	memcpy(iv, str, iv_len);
	return iv;
}

char *luacrypto_newbuffer(lua_State *L, size_t size);

static inline int luacrypto_pushbuffer(lua_State *L, char *buffer, int ret, size_t offset, size_t len)
{
	if (ret < 0) {
		lunatik_free(buffer);
		lunatik_throw(L, ret);
	}
	if (offset)
		memmove(buffer, buffer + offset, len); /* the string frees the buffer from its start */
	lunatik_pushexternalstring(L, buffer, len);
	return 1;
}

LUACRYPTO_DECLARE(shash);
LUACRYPTO_DECLARE(skcipher);
LUACRYPTO_DECLARE(aead);
LUACRYPTO_DECLARE(rng);
LUACRYPTO_DECLARE(sig);
LUACRYPTO_DECLARE(comp);

#endif /* _LUACRYPTO_H */

