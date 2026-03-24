/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_val_h
#define lunatik_val_h

typedef struct lunatik_string_s {
	struct kref kref;
	char *data;
} lunatik_string_t;

typedef struct lunatik_value_s {
	int type;
	union {
		int boolean;
		lua_Integer integer;
		lunatik_object_t *object;
		lunatik_string_t *string;
	};
} lunatik_value_t;

#define lunatik_isuserdata(v)	((v)->type == LUA_TUSERDATA)
#define lunatik_isstring(v)	((v)->type == LUA_TSTRING)

void lunatik_freestring(struct kref *kref);
#define lunatik_getstring(s)	kref_get(&(s)->kref)
#define lunatik_putstring(s)	kref_put(&(s)->kref, lunatik_freestring)

static inline void lunatik_holdvalue(lunatik_value_t *value)
{
	if (lunatik_isuserdata(value))
		lunatik_getobject(value->object);
	else if (lunatik_isstring(value))
		lunatik_getstring(value->string);
}

static inline void lunatik_dropvalue(lunatik_value_t *value)
{
	if (lunatik_isuserdata(value))
		lunatik_putobject(value->object);
	else if (lunatik_isstring(value))
		lunatik_putstring(value->string);
}

/* release value's reference after lunatik_pushvalue (strings only; objects transfer their ref) */
static inline void lunatik_putvalue(lunatik_value_t *value)
{
	if (lunatik_isstring(value))
		lunatik_putstring(value->string);
}

void lunatik_checkvalue(lua_State *L, int ix, lunatik_value_t *value);
void lunatik_pushvalue(lua_State *L, lunatik_value_t *value);

#endif

