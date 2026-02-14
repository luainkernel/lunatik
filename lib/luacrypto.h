/*
 * SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#ifndef _LUACRYPTO_H
#define _LUACRYPTO_H

#include <linux/err.h>
#include <lunatik.h>

typedef void *(*luacrypto_new_t)(lua_State *, void *);
typedef void (*luacrypto_free_t)(void *);

/**
 * LUACRYPTO_NEW - Macro to define a common constructor for crypto transform objects.
 * @name: The base name of the crypto module (e.g., aead, skcipher, shash).
 * @T: The C struct type of the crypto transform (e.g., struct crypto_aead).
 * @alloc: The kernel crypto allocation function (e.g., crypto_alloc_aead).
 * @class: The lunatik_class_t instance for this object type.
 * @private: The expression to assign to object->private (e.g., tfm or sdesc).
 * @new: Optional extra allocation and assignment logic (e.g., for shash_desc).
 *
 * This macro generates the `luacrypto_<_name>_new` function, which acts as the
 * constructor for Lua crypto objects. It handles the common steps of checking
 * the algorithm name, allocating the Lunatik object, allocating the kernel
 * crypto transform, handling errors, and assigning the private data.
 */
#define LUACRYPTO_NEW(name, T, alloc, class, new)							\
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
	luacrypto_new_t _new = (luacrypto_new_t)new;							\
	if (_new)											\
		object->private = _new(L, tfm);								\
	else												\
		object->private = tfm;									\
													\
	return 1;											\
}

/**
 * LUACRYPTO_RELEASE - Macro to define a common release function for crypto transform objects.
 * @name: The base name of the crypto module (e.g., aead, skcipher, shash).
 * @T: The C struct type of the private data stored in the Lunatik object (e.g., struct crypto_aead, struct shash_desc).
 * @obj_free: The function to free the `T` object itself (e.g., crypto_free_aead, lunatik_free).
 * @priv_free: Optional extra release logic, which can access `obj` (the casted `T` pointer).
 *
 * This macro generates the `luacrypto_<_name>_release` function, which is used
 * as the `release` callback for Lunatik objects. It handles freeing the primary
 * private data and allows for additional custom cleanup.
 */
#define LUACRYPTO_RELEASER(name, T, obj_free, priv_free)			\
static void luacrypto_##name##_release(void *private)				\
{										\
	T *obj = (T *)private;							\
	if (obj) {								\
		luacrypto_free_t _priv_free = (luacrypto_free_t)priv_free;	\
		if (_priv_free)							\
			_priv_free(obj);					\
		obj_free(obj);							\
	}									\
}

/**
 * LUACRYPTO_FREEREQUEST - Macro to define a common request freeing function.
 * @name: The base name of the crypto module (e.g., aead, skcipher).
 * @request_T: The C struct type of the request (e.g., struct aead_request, struct skcipher_request).
 * @request_free: The kernel crypto request freeing function (e.g., aead_request_free, skcipher_request_free).
 *
 * This macro generates the `luacrypto_<_name>_freerequest` function, which handles
 * freeing the crypto request and the associated IV buffer.
 */
#define LUACRYPTO_FREEREQUEST(name, request_T, request_free)			\
static inline void luacrypto_##name##_freerequest(request_T *request, u8 *iv)	\
{										\
	request_free(request);							\
	lunatik_free(iv);							\
}

#endif /* _LUACRYPTO_H */

