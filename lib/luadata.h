/*
* SPDX-FileCopyrightText: (c) 2024-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luadata_h
#define luadata_h

#include <lunatik.h>

#define	LUADATA_OPT_NONE	0x00
#define	LUADATA_OPT_READONLY	0x01
#define	LUADATA_OPT_FREE	0x02
#define LUADATA_OPT_SKB  	0x04
#define	LUADATA_OPT_KEEP  	0x80

#define luadata_clear(o)	(luadata_reset((o), NULL, 0, 0, LUADATA_OPT_KEEP))

lunatik_object_t *luadata_new(lua_State *L);
int luadata_reset(lunatik_object_t *object, void *ptr, ptrdiff_t offset, size_t size, uint8_t opt);

static inline void luadata_close(lunatik_object_t *object)
{
	luadata_clear(object);
	lunatik_putobject(object);
}

#define luadata_attach(L, obj, field)		\
do {						\
	obj->field = luadata_new(L); 		\
	lunatik_register(L, -1, obj->field);	\
	lua_pop(L, 1);				\
} while (0)

#define luadata_detach(runtime, obj, field)			\
do {								\
	lua_State *L = lunatik_getstate(runtime);		\
	if (L != NULL) /* might be called on lunatik_stop */	\
		lunatik_unregister(L, obj->field);		\
	obj->field = NULL; 					\
} while (0)

#endif

