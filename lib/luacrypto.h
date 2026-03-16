/*
 * SPDX-FileCopyrightText: (c) 2025 jperon <cataclop@hotmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#ifndef _LUACRYPTO_H
#define _LUACRYPTO_H

#include <linux/err.h>
#include <lunatik.h>

#define LUACRYPTO_NEW(name, T, alloc, class)								\
static int luacrypto_##name##_new(lua_State *L)								\
{													\
	const char *algname = luaL_checkstring(L, 1);							\
	lunatik_object_t *object = lunatik_newobject(L, &class, 0, LUNATIK_OPT_NONE);						\
													\
	T *tfm = alloc(algname, 0, 0);									\
	if (IS_ERR(tfm)) {										\
		long err = PTR_ERR(tfm);								\
		luaL_error(L, "Failed to allocate " #name " transform for %s (err %ld)", algname, err);	\
	}												\
	object->private = tfm;										\
													\
	return 1;											\
}

#define LUACRYPTO_RELEASER(name, T, obj_free)			\
static void luacrypto_##name##_release(void *private)		\
{								\
	T *obj = (T *)private;					\
	if (obj)						\
		obj_free(obj);					\
}

#endif /* _LUACRYPTO_H */

