/*
** $Id: lualib.h,v 1.20 2001/03/06 20:09:38 roberto Exp roberto $
** Lua standard libraries
** See Copyright Notice in lua.h
*/


#ifndef lualib_h
#define lualib_h

#include "lua.h"


#ifndef LUALIB_API
#define LUALIB_API	extern
#endif


#define LUA_ALERT               "_ALERT"

LUALIB_API int lua_baselibopen (lua_State *L);
LUALIB_API int lua_iolibopen (lua_State *L);
LUALIB_API int lua_strlibopen (lua_State *L);
LUALIB_API int lua_mathlibopen (lua_State *L);
LUALIB_API int lua_dblibopen (lua_State *L);


#endif
