/*
 * Copyright (C) 2020  Matheus Rodrigues <matheussr61@gmail.com>
 * Copyright (C) 2017-2019  CUJO LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <lua.h>
#include <lauxlib.h>

#include <lmemlib.h>

#include "luautil.h"
#include "lunatik.h"

extern int lunatikN_send_data(lunatik_State *state, const char *payload, size_t size);

static int luanetlink_send(lua_State *L)
{
	lunatik_State *s = luaU_getenv(L, lunatik_State);
	const char *payload;
	size_t size;
	int err;

	if (s == NULL)
		return luaL_error(L, "invalid lunatik_State");

	payload = luamem_checkstring(L, 1, &size);

	if ((err = lunatikN_send_data(s, payload, size)) < 0)
		return luaL_error(L, "failed to send message. Return code %d", err);

	lua_pushinteger(L, (lua_Integer)size);

	return 1;
}

static const luaL_Reg luanetlink_lib[] = {
	{"send", luanetlink_send},
	{NULL, NULL}
};

int luaopen_netlink(lua_State *L)
{
	luaL_newlib(L, luanetlink_lib);
	return 1;
}
EXPORT_SYMBOL(luaopen_netlink);
