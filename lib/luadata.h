/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luadata_h
#define luadata_h

#include <lunatik.h>

LUNATIK_LIB(data);

#define	LUADATA_OPT_NONE	0x00
#define	LUADATA_OPT_READONLY	0x01
#define	LUADATA_OPT_FREE	0x02
#define	LUADATA_OPT_KEEP  	0x80

#define luadata_clear(o)	(luadata_reset((o), NULL, 0, LUADATA_OPT_KEEP))

typedef struct luadata_s {
    char *ptr;
    size_t size;
    uint8_t opt;
} luadata_t;

LUNATIK_PRIVATECHECKER(luadata_check, luadata_t *);

static inline void luadata_checkbounds(lua_State *L, int ix, size_t size,
                                       lua_Integer offset, lua_Integer length)
{
    int bounds = offset >= 0 && length > 0 && offset + length <= size;
    luaL_argcheck(L, bounds, ix, "out of bounds");
}

lunatik_object_t *luadata_new(lua_State *L);
int luadata_reset(lunatik_object_t *object, void *ptr, size_t size, uint8_t opt);

static inline void luadata_close(lunatik_object_t *object)
{
	luadata_clear(object);
	lunatik_putobject(object);
}

#define luadata_attach(L, obj, field)			\
do {							\
	obj->field = luadata_new(L); 			\
	lunatik_setregistry(L, -1, obj->field);		\
	lua_pop(L, 1);					\
} while (0)

#endif

