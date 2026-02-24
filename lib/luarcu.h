/*
* SPDX-FileCopyrightText: (c) 2024 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef luarcu_h
#define luarcu_h

#define LUARCU_DEFAULT_SIZE	(256)

lunatik_object_t *luarcu_newtable(size_t size, bool sleep);
void luarcu_getvalue(lunatik_object_t *table, const char *key, size_t keylen, lunatik_value_t *value);
int luarcu_setvalue(lunatik_object_t *table, const char *key, size_t keylen, lunatik_value_t *value);

static inline lunatik_object_t *luarcu_getobject(lunatik_object_t *table, const char *key, size_t keylen)
{
	lunatik_value_t value;
	luarcu_getvalue(table, key, keylen, &value);
	return lunatik_isuserdata(&value) ? value.object : NULL;
}

static inline int luarcu_setobject(lunatik_object_t *table, const char *key, size_t keylen, lunatik_object_t *obj)
{
	lunatik_value_t value = {.type = LUA_TUSERDATA, .object = obj};
	return luarcu_setvalue(table, key, keylen, &value);
}

#endif

