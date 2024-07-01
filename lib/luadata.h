/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luadata_h
#define luadata_h

#include <lunatik.h>

LUNATIK_LIB(data);

lunatik_object_t *luadata_new(void *ptr, size_t size, bool sleep, bool editable);
int luadata_reset(lunatik_object_t *object, void *ptr, size_t size, bool editable);
int luadata_clear(lunatik_object_t *object);

static inline void luadata_close(lunatik_object_t *object)
{
	luadata_clear(object);
	lunatik_putobject(object);
}

#endif

