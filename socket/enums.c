#include "../lua/lua.h"
#include "../lua/lualib.h"
#include "../lua/lauxlib.h"
#include <linux/socket.h>
#include <net/sock.h>

int socket_tofamily(lua_State *L, int n)
{
    const char *str = luaL_checkstring(L, n);
    switch (*str)
    {
    case 'i':
        return AF_INET;
    default:
        return luaL_argerror(L, n, "invalid family name");
    }
}
int socket_totype(lua_State *L, int n)
{
    const char *str = luaL_checkstring(L, n);
    switch (*str)
    {
    case 't':
        return SOCK_STREAM;
    case 'u':
        return SOCK_DGRAM;
    default:
        return luaL_argerror(L, n, "invalid family name");
    }
}