#include "../lua/lua.h"
#include "../lua/lualib.h"
#include "../lua/lauxlib.h"

#include <linux/string.h>
#include <linux/in.h>
#include <linux/inet.h>
#include <linux/socket.h>
#include <net/sock.h>
#include <linux/unistd.h>
#include <linux/errno.h>

#include "enums.h"

#define LUA_SOCKET "luasocket"

typedef struct socket *sock_t;

lua_Integer luaL_optfieldinteger(lua_State *L, int idx, const char *k, int def)
{
    int isnum;
    lua_Integer d;
    lua_getfield(L, idx, k);
    d = lua_tointegerx(L, -1, &isnum);
    if (!isnum)
    {
        return def;
    }
    return d;
}

static const char *inet_ntoa(struct in_addr ina)
{
    static char buf[4 * sizeof "123"];
    unsigned char *ucp = (unsigned char *)&ina;

    sprintf(buf, "%d.%d.%d.%d",
            ucp[0] & 0xff,
            ucp[1] & 0xff,
            ucp[2] & 0xff,
            ucp[3] & 0xff);
    return buf;
}
static unsigned int inet_addr(const char *str)
{
    int a, b, c, d;
    char arr[4];
    sscanf(str, "%d.%d.%d.%d", &a, &b, &c, &d);
    arr[0] = a;
    arr[1] = b;
    arr[2] = c;
    arr[3] = d;
    return *(unsigned int *)arr;
}

int luasocket(lua_State *L)
{
    int err;
    sock_t sock = (sock_t)kmalloc(sizeof(struct socket), GFP_KERNEL);
    if (sock == NULL)
    {
        luaL_error(L, "kmalloc fail");
    }

    memset(sock, 0, sizeof(struct socket));
    err = sock_create(
        socket_tofamily(L, 1),
        socket_totype(L, 2),
        0, &sock);

    if (err < 0)
    {
        luaL_error(L, "Socket creation error %d", err);
    }

    *((sock_t *)lua_newuserdata(L, sizeof(sock_t))) = sock;
    luaL_getmetatable(L, LUA_SOCKET);
    lua_setmetatable(L, -2);
    return 1;
}

int luasocket_bind(lua_State *L)
{
    int err;
    struct sockaddr_in addr;
    sock_t s = *(sock_t *)luaL_checkudata(L, 1, LUA_SOCKET);
    const char *ip = luaL_checkstring(L, 2);
    const int port = luaL_checkinteger(L, 3);

    if (port <= 0 || port > 65535)
    {
        luaL_argerror(L, 2, "Port number out of range");
    }

    addr.sin_family = s->sk->sk_family;
    addr.sin_port = htons((u_short)port);
    addr.sin_addr.s_addr = inet_addr(ip);

    if ((err = kernel_bind(s, (struct sockaddr *)&addr, sizeof(addr))) < 0)
    {
        luaL_error(L, "Socket bind error: %d", err);
    }

    return 0;
}
int luasocket_listen(lua_State *L)
{
    int err;
    sock_t s = *(sock_t *)luaL_checkudata(L, 1, LUA_SOCKET);
    const int backlog = luaL_checkinteger(L, 2);

    if (backlog <= 0)
    {
        luaL_argerror(L, 2, "Backlog number out of range");
    }

    if ((err = kernel_listen(s, backlog)) < 0)
    {
        luaL_error(L, "Socket listen error: %d", err);
    }

    return 0;
}
int luasocket_accept(lua_State *L)
{
    int err;
    sock_t s = *(sock_t *)luaL_checkudata(L, 1, LUA_SOCKET);
    const int flags = luaL_optnumber(L, 2, 0);
    sock_t newsock;

    if ((err = kernel_accept(s, &newsock, flags)) < 0)
    {
        luaL_error(L, "Socket accept error: %d", err);
    }

    *((sock_t *)lua_newuserdata(L, sizeof(sock_t))) = newsock;
    luaL_getmetatable(L, LUA_SOCKET);
    lua_setmetatable(L, -2);

    return 1;
}
int luasocket_connect(lua_State *L)
{
    int err;
    struct sockaddr_in addr;
    sock_t s = *(sock_t *)luaL_checkudata(L, 1, LUA_SOCKET);
    const char *ip = luaL_checkstring(L, 2);
    const int port = luaL_checkinteger(L, 3);
    const int flags = luaL_optinteger(L, 4, 0);

    if (port <= 0 || port > 65535)
    {
        luaL_argerror(L, 2, "Port number out of range");
    }

    addr.sin_family = s->sk->sk_family;
    addr.sin_port = htons((u_short)port);
    addr.sin_addr.s_addr = inet_addr(ip);

    if ((err = kernel_connect(s, (struct sockaddr *)&addr, sizeof(addr), flags)) < 0)
    {
        luaL_error(L, "Socket connect error: %d", err);
    }

    return 0;
}
int luasocket_sendmsg(lua_State *L)
{
    int err;
    struct msghdr msg;
    struct sockaddr_in addr;
    sock_t s = *(sock_t *)luaL_checkudata(L, 1, LUA_SOCKET);

    luaL_checktype(L, 2, LUA_TTABLE);
    memset(&msg, 0, sizeof(msg));
    msg.msg_flags = luaL_optfieldinteger(L, 2, "flags", 0);

    // if (lua_getfield(L, 2, "name") == LUA_TTABLE)
    // {
    //     addr.sin_family = s->sk->sk_family;
    //     addr.sin_port = htons((u_short)port);
    //     addr.sin_addr.s_addr = inet_addr(ip);

    //     msg.msg_name = &addr;
    //     msg.msg_namelen = sizeof(addr);
    // }

    if ((err = sock_sendmsg(s, &msg)) < 0)
    {
        luaL_error(L, "Socket connect error: %d", err);
    }

    return 0;
}

static const struct luaL_Reg libluasocket_methods[] = {
    {"bind", luasocket_bind},
    {"listen", luasocket_listen},
    {"accept", luasocket_accept},
    {"connect", luasocket_connect},
    {"sendmsg", luasocket_sendmsg},
    // {"write", luaudp_write},
    // {"close", luaudp_close},
    // {"__gc", luaudp_close},
    {NULL, NULL} /* sentinel */
};

int luaopen_libluaudp(lua_State *L)
{
    luaL_newmetatable(L, LUA_SOCKET);
    /* Duplicate the metatable on the stack (We know have 2). */
    lua_pushvalue(L, -1);
    /* Pop the first metatable off the stack and assign it to __index
     * of the second one. We set the metatable for the table to itself.
     * This is equivalent to the following in lua:
     * metatable = {}
     * metatable.__index = metatable
     */
    lua_setfield(L, -2, "__index");

    /* Set the methods to the metatable that should be accessed via object:func */
    luaL_setfuncs(L, libluasocket_methods, 0);

    lua_pushcfunction(L, luasocket);
    lua_setglobal(L, "socket");
    return 0;
}