/*
 * SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#ifndef _LUACRYPTO_H
#define _LUACRYPTO_H

#include <linux/err.h>
#include <linux/version.h>
#include <lunatik.h>

#define LUACRYPTO_NEW(name, T, alloc, class)							\
int luacrypto_##name##_new(lua_State *L)							\
{												\
	const char *algname = luaL_checkstring(L, 1);						\
	T *tfm = alloc(algname, 0, 0);								\
	if (IS_ERR(tfm))									\
		lunatik_throw(L, PTR_ERR(tfm));							\
	lunatik_object_t *object = lunatik_newobject(L, &class, 0, LUNATIK_OPT_NONE);		\
	object->private = tfm;									\
	return 1;										\
}

#define LUACRYPTO_RELEASER(name, T, obj_free)			\
static void luacrypto_##name##_release(void *private)		\
{								\
	T *obj = (T *)private;					\
	if (obj)						\
		obj_free(obj);					\
}

/* Per-tfm fixed-size state (request, IV) allocated once at creation, so
 * encrypt/decrypt never allocates on the hot path (e.g. softirq). */
typedef struct luacrypto_ctx_s {
	void *tfm;
	void *request;
	u8 *iv;
} luacrypto_ctx_t;

#define LUACRYPTO_NEWCTX(name, T, alloc, class)							\
int luacrypto_##name##_new(lua_State *L)							\
{												\
	const char *algname = luaL_checkstring(L, 1);						\
	gfp_t gfp = lunatik_gfp(lunatik_toruntime(L));						\
	lunatik_object_t *object = lunatik_newobject(L, &class,				\
		sizeof(luacrypto_ctx_t), LUNATIK_OPT_NONE);					\
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)object->private;				\
	T *tfm = alloc(algname, 0, 0);								\
	if (IS_ERR(tfm))									\
		lunatik_throw(L, PTR_ERR(tfm));							\
	ctx->tfm = tfm;										\
	unsigned int ivsize = crypto_##name##_ivsize(tfm);					\
	ctx->request = name##_request_alloc(tfm, gfp);						\
	ctx->iv = ivsize != 0 ? (u8 *)lunatik_malloc(L, ivsize) : NULL;				\
	if (ctx->request == NULL || (ivsize != 0 && ctx->iv == NULL))				\
		lunatik_enomem(L);								\
	return 1;										\
}

#define LUACRYPTO_RELEASERCTX(name, T, tfm_free)		\
static void luacrypto_##name##_release(void *private)		\
{								\
	luacrypto_ctx_t *ctx = (luacrypto_ctx_t *)private;	\
	if (ctx == NULL)					\
		return;						\
	name##_request_free(ctx->request);			\
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

extern const lunatik_class_t luacrypto_shash_class;
extern const lunatik_class_t luacrypto_skcipher_class;
extern const lunatik_class_t luacrypto_aead_class;
extern const lunatik_class_t luacrypto_rng_class;

int luacrypto_shash_new(lua_State *L);
int luacrypto_skcipher_new(lua_State *L);
int luacrypto_aead_new(lua_State *L);
int luacrypto_rng_new(lua_State *L);

#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 15, 0))
extern const lunatik_class_t luacrypto_comp_class;
int luacrypto_comp_new(lua_State *L);
#endif

#endif /* _LUACRYPTO_H */

