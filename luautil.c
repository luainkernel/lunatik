/*
 * Copyright (C) 2017-2019 CUJO LLC.
 * Copyright (C) 1994-2018 Lua.org, PUC-Rio.
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#include "luautil.h"

static int msghandler(lua_State *L)
{
	const char *msg = lua_tostring(L, 1);
	if (msg == NULL) {
		if (luaL_callmeta(L, 1, "__tostring") &&
		    lua_type(L, -1) == LUA_TSTRING)
			return 1;
		else
			msg = lua_pushfstring(L, "(error object is a %s value)",
				luaL_typename(L, 1));
	}
	luaL_traceback(L, L, msg, 1);
	return 1;
}

int luaU_pcall(lua_State *L, int nargs, int nresults)
{
	int status;
	int base = lua_gettop(L) - nargs;
	lua_pushcfunction(L, msghandler);
	lua_insert(L, base);
	status = lua_pcall(L, nargs, nresults, base);
	lua_remove(L, base);
	return status;
}
