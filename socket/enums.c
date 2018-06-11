#include "../lua/lauxlib.h"
#include "../lua/lua.h"
#include "../lua/lualib.h"
#include <linux/socket.h>
#include <net/sock.h>

int socket_tofamily(lua_State *L, int n)
{
	const char *str = luaL_checkstring(L, n);
	switch (*str) {
	case 'i':
		return AF_INET;
	default:
		return luaL_argerror(L, n, "invalid family name");
	}
}
int socket_totype(lua_State *L, int n)
{
	const char *str = luaL_checkstring(L, n);
	switch (*str) {
	case 't':
		return SOCK_STREAM;
	case 'u':
		return SOCK_DGRAM;
	default:
		return luaL_argerror(L, n, "invalid type name");
	}
}
int socket_tolevel(lua_State *L, int n)
{
	const char *str = luaL_checkstring(L, n);
	switch (*str) {
	case 's':
		return SOL_SOCKET;
	case 't':
		return SOL_TCP;
	case 'u':
		return SOL_UDP;
	case 'r':
		return SOL_RAW;
	case 'i':
		return IPPROTO_IP;
	default:
		return luaL_argerror(L, n, "invalid level name");
	}
}

static int socket_option(lua_State *L, const char *str)
{
	switch (*str) {
	case 'b':
		return SO_BROADCAST;
	case 'd':
		switch (str[1]) {
		case 0:
			return SO_DEBUG;
		case 't':
			return SO_DONTROUTE;
		default:
			return luaL_error(L, "invalid option name");
		}
	case 'e':
		return SO_ERROR;
	case 'k':
		return SO_KEEPALIVE;
	case 'l':
		return SO_LINGER;
	case 'n':
		return SO_NO_CHECK;
	case 'o':
		return SO_OOBINLINE;
	case 'p':
		return SO_PRIORITY;
	case 'r':
		switch (str[1]) {
		case 0:
			return SO_RCVBUF;
		case 'f':
			return SO_RCVBUFFORCE;
		case 'a':
			return SO_REUSEADDR;
		case 'p':
			return SO_REUSEPORT;
		default:
			return luaL_error(L, "invalid option name");
		}
	case 's':
		switch (str[1]) {
		case 0:
			return SO_SNDBUF;
		case 'f':
			return SO_SNDBUFFORCE;
		default:
			return luaL_error(L, "invalid option name");
		}
	case 't':
		return SO_TYPE;
	default:
		return luaL_error(L, "invalid option name");
	}
}

int socket_tooption(lua_State *L, int n, int level)
{
	const char *str = luaL_checkstring(L, n);
	switch (level) {
	case SOL_SOCKET:
		return socket_option(L, str);
	default:
		return luaL_argerror(L, n, "invalid option name");
	}
}