/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luadata_h
#define luadata_h

#include <lunatik.h>

LUNATIK_LIB(data);

typedef enum {
	LUADATA_CONST = 1,
} luadata_flags_t;

#define luadata_clear(o)	(luadata_reset((o), NULL, 0))

lunatik_object_t *luadata_new(void *ptr, size_t size, bool sleep, uint32_t flags);
int luadata_reset(lunatik_object_t *object, void *ptr, size_t size);
int luadata_setflags(lunatik_object_t *object, uint32_t flags);

static inline void luadata_close(lunatik_object_t *object)
{
	luadata_clear(object);
	lunatik_putobject(object);
}

#endif

