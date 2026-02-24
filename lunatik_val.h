/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_val_h
#define lunatik_val_h

typedef struct lunatik_value_s {
	int type;
	union {
		int boolean;
		lua_Integer integer;
		lunatik_object_t *object;
	};
} lunatik_value_t;

#define lunatik_isuserdata(v)	((v)->type == LUA_TUSERDATA)

void lunatik_checkvalue(lua_State *L, int ix, lunatik_value_t *value);
void lunatik_pushvalue(lua_State *L, lunatik_value_t *value);

#endif

