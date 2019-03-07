#ifndef _SOCKET_ENUMS_H_
#define _SOCKET_ENUMS_H_
#include "../lua/lua.h"
#include "../lua/lualib.h"
#include "../lua/lauxlib.h"


int socket_tofamily(lua_State *L, int n);
int socket_totype(lua_State *L, int n);
int socket_tolevel(lua_State *L, int n);
int socket_tooption(lua_State *L, int n, int level);
int socket_toflags(lua_State *L, int n);
#endif