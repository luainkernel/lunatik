/*
 * SPDX-FileCopyrightText: (c) 2025-2026 jperon <cataclop@hotmail.com>
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */

#ifndef _LUACRYPTO_H
#define _LUACRYPTO_H

#include <linux/err.h>
#include <lunatik.h>

#define LUACRYPTO_NEW(name, T, alloc, class)							\
static int luacrypto_##name##_new(lua_State *L)							\
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

#endif /* _LUACRYPTO_H */

