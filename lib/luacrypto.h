/*
 * SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#ifndef _LUACRYPTO_H
#define _LUACRYPTO_H

#include <linux/err.h>
#include <lua.h>
#include <lauxlib.h>
#include <lunatik.h>

/**
 * LUACRYPTO_NEW - Macro to define a common constructor for crypto transform objects.
 * @name: The base name of the crypto module (e.g., aead, skcipher, shash).
 * @T: The C struct type of the crypto transform (e.g., struct crypto_aead).
 * @alloc: The kernel crypto allocation function (e.g., crypto_alloc_aead).
 * @class: The lunatik_class_t instance for this object type.
 * @private: The expression to assign to object->private (e.g., tfm or sdesc).
 * @extra: Optional extra allocation and assignment logic (e.g., for shash_desc).
 *
 * This macro generates the `luacrypto_<_name>_new` function, which acts as the
 * constructor for Lua crypto objects. It handles the common steps of checking
 * the algorithm name, allocating the Lunatik object, allocating the kernel
 * crypto transform, handling errors, and assigning the private data.
 */
#define LUACRYPTO_NEW(name, T, alloc, class, priv, ...)						\
static int luacrypto_##name##_new(lua_State *L)								\
{													\
	const char *algname = luaL_checkstring(L, 1);							\
	lunatik_object_t *object = lunatik_newobject(L, &class, 0);					\
													\
	T *tfm = alloc(algname, 0, 0);									\
	if (IS_ERR(tfm)) {										\
		long err = PTR_ERR(tfm);								\
		luaL_error(L, "Failed to allocate " #name " transform for %s (err %ld)", algname, err);	\
	}												\
	__VA_ARGS__											\
	object->private = priv;									\
													\
	return 1;											\
}

/**
 * LUACRYPTO_RELEASE - Macro to define a common release function for crypto transform objects.
 * @name: The base name of the crypto module (e.g., aead, skcipher, shash).
 * @T: The C struct type of the private data stored in the Lunatik object (e.g., struct crypto_aead, struct shash_desc).
 * @release: The function to free the `T` object itself (e.g., crypto_free_aead, lunatik_free).
 * @extra: Optional extra release logic, which can access `obj` (the casted `T` pointer).
 *
 * This macro generates the `luacrypto_<_name>_release` function, which is used
 * as the `release` callback for Lunatik objects. It handles freeing the primary
 * private data and allows for additional custom cleanup.
 */
#define LUACRYPTO_RELEASE(name, T, release, ...)		\
static void luacrypto_##name##_release(void *private_ptr)	\
{								\
 T *obj = (T *)private_ptr;					\
 if (obj) {							\
	__VA_ARGS__						\
	release(obj);						\
 }								\
}

#endif /* _LUACRYPTO_H */

