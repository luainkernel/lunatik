/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_val_h
#define lunatik_val_h

typedef struct lunatik_string_s {
	struct kref kref;
	size_t len;
	char str[];
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

void lunatik_checkvalue(lua_State *L, int ix, lunatik_value_t *value);
void lunatik_pushvalue(lua_State *L, lunatik_value_t *value);

#endif

