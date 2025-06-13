/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luarcu_h
#define luarcu_h

#define LUARCU_DEFAULT_SIZE	(256)

lunatik_object_t *luarcu_newtable(size_t size, bool sleep);
lunatik_object_t *luarcu_gettable(lunatik_object_t *table, const char *key, size_t keylen);
int luarcu_settable(lunatik_object_t *table, const char *key, size_t keylen, lunatik_object_t *object);

#endif

