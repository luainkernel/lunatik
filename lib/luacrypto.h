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

static inline u8 *luacrypto_checkiv(lua_State *L, int idx, size_t expected)
{
	size_t iv_len;
	const char *iv = luaL_checklstring(L, idx, &iv_len);
	if (iv_len != expected)
		lunatik_throw(L, -EINVAL);

	u8 *out = (u8 *)lunatik_checkalloc(L, iv_len);
	memcpy(out, iv, iv_len);
	return out;
}

#define LUACRYPTO_REQUEST_ALLOC(L, request, name, tfm)				\
do {										\
	gfp_t __gfp = lunatik_gfp(lunatik_toruntime(L));			\
	(request)->name = name##_request_alloc((tfm), __gfp);			\
	if ((request)->name == NULL) {						\
		lunatik_free((request)->iv);					\
		lunatik_enomem(L);						\
	}									\
} while (0)

#define LUACRYPTO_REQUEST_FREE(request, name)					\
do {										\
	name##_request_free((request)->name);					\
	lunatik_free((request)->iv);						\
} while (0)

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

