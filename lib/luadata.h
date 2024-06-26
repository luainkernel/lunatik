/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luadata_h
#define luadata_h

LUNATIK_LIB(data);

#define luadata_clear(o)	(luadata_reset((o), NULL, 0))

lunatik_object_t *luadata_new(void *ptr, size_t size, bool sleep);
int luadata_reset(lunatik_object_t *object, void *ptr, size_t size);

static inline void luadata_close(lunatik_object_t *object)
{
	luadata_reset(object, NULL, 0);
	lunatik_putobject(object);
}

#endif

