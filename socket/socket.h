#ifndef __LUNATIK_SOCKET__H__
#define __LUNATIK_SOCKET__H__

#include <lua/lauxlib.h>
#include <lua/lua.h>
#include <lua/lualib.h>

#include <linux/errno.h>
#include <linux/in.h>
#include <linux/inet.h>
#include <linux/socket.h>
#include <linux/string.h>
#include <linux/unistd.h>
#include <linux/version.h>
#include <linux/wait.h>

#define LUA_SOCKET "luasocket"
#define LUA_SOCKET_MAXBUFFER 4096

#define LUA_POLL "lpoll"

typedef struct socket *sock_t;

extern const char *inet_ntop(int af, const void *src, char *dst, int size);
extern int inet_pton(int af, const char *src, void *dst);

extern int lpoll(lua_State *L);
extern int luaopen_lpoll(lua_State *L);
extern int luaopen_libsocket(lua_State *L);
#endif
