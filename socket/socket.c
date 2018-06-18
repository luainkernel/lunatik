#include <lua/lauxlib.h>
#include <lua/lua.h>
#include <lua/lualib.h>

#include <linux/errno.h>
#include <linux/in.h>
#include <linux/inet.h>
#include <linux/socket.h>
#include <linux/string.h>
#include <linux/unistd.h>
#include <net/sock.h>

#ifdef CONFIG_LUADATA
#include <luadata.h>
#endif /* CONFIG_LUADATA */

#include "enums.h"

#define LUA_SOCKET "luasocket"
#define LUA_SOCKET_MAXBUFFER 4096

typedef struct socket *sock_t;

extern const char *inet_ntop(int af, const void *src, char *dst, int size);
extern int inet_pton(int af, const char *src, void *dst);

lua_Integer socket_optfieldinteger(lua_State *L, int idx, const char *k,
				   int def)
{
	int isnum;
	lua_Integer d;

	lua_getfield(L, idx, k);
	d = lua_tointegerx(L, -1, &isnum);
	lua_pop(L, 1);
	if (!isnum)
		return def;

	return d;
}

int luasocket(lua_State *L)
{
	int err;
	sock_t sock;

	err = sock_create(socket_tofamily(L, 1), socket_totype(L, 2), 0, &sock);

	if (err < 0)
		luaL_error(L, "Socket creation error %d", err);

	*((sock_t *) lua_newuserdata(L, sizeof(sock_t))) = sock;
	luaL_getmetatable(L, LUA_SOCKET);
	lua_setmetatable(L, -2);
	return 1;
}

int luasocket_bind(lua_State *L)
{
	int err;
	struct sockaddr_in addr;
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	const char *ip = luaL_checkstring(L, 2);
	const int port = luaL_checkinteger(L, 3);

	if (port <= 0 || port > 65535)
		luaL_argerror(L, 2, "Port number out of range");

	addr.sin_family = s->sk->sk_family;
	addr.sin_port = htons((u_short) port);
	inet_pton(s->sk->sk_family, ip, &addr.sin_addr.s_addr);

	if ((err = kernel_bind(s, (struct sockaddr *) &addr, sizeof(addr))) < 0)
		luaL_error(L, "Socket bind error: %d", err);

	return 0;
}
int luasocket_listen(lua_State *L)
{
	int err;
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	const int backlog = luaL_checkinteger(L, 2);

	if (backlog <= 0)
		luaL_argerror(L, 2, "Backlog number out of range");

	if ((err = kernel_listen(s, backlog)) < 0)
		luaL_error(L, "Socket listen error: %d", err);

	return 0;
}
int luasocket_accept(lua_State *L)
{
	int err;
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	const int flags = luaL_optnumber(L, 2, 0);
	sock_t newsock;

	if ((err = kernel_accept(s, &newsock, flags)) < 0)
		luaL_error(L, "Socket accept error: %d", err);

	*((sock_t *) lua_newuserdata(L, sizeof(sock_t))) = newsock;
	luaL_getmetatable(L, LUA_SOCKET);
	lua_setmetatable(L, -2);

	return 1;
}
int luasocket_connect(lua_State *L)
{
	int err;
	struct sockaddr_in addr;
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	const char *ip = luaL_checkstring(L, 2);
	const int port = luaL_checkinteger(L, 3);
	const int flags = luaL_optinteger(L, 4, 0);

	if (port <= 0 || port > 65535)
		luaL_argerror(L, 2, "Port number out of range");

	addr.sin_family = s->sk->sk_family;
	addr.sin_port = htons((u_short) port);
	inet_pton(s->sk->sk_family, ip, &addr.sin_addr.s_addr);

	if ((err = kernel_connect(s, (struct sockaddr *) &addr, sizeof(addr),
				  flags)) < 0)
		luaL_error(L, "Socket connect error: %d", err);

	return 0;
}
int luasocket_sendmsg(lua_State *L)
{
	int i;
	int err;
	size_t size;
	struct msghdr msg;
	struct kvec vec;
	struct sockaddr_in addr;
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	char *buffer = NULL;

	luaL_checktype(L, 2, LUA_TTABLE);

	if (lua_istable(L, 3)) {
		size = luaL_len(L, 3);
		luaL_argcheck(L, size > 0, 3, "data can not be empty");
	} else if (IS_ENABLED(CONFIG_LUADATA)) {
		if ((buffer = ldata_topointer(L, 3, &size)) == NULL)
			luaL_argerror(L, 3,
				      "data must be a table or luadata obejct");
	} else
		luaL_argerror(L, 3, "data must be a table");

	memset(&msg, 0, sizeof(msg));
	msg.msg_flags = socket_optfieldinteger(L, 2, "flags", 0);

	if (lua_getfield(L, 2, "name") == LUA_TTABLE) {
		addr.sin_family = s->sk->sk_family;
		addr.sin_port =
		    htons((u_short) socket_optfieldinteger(L, -1, "port", 0));

		if (lua_getfield(L, -1, "addr") == LUA_TSTRING)
			inet_pton(s->sk->sk_family, lua_tostring(L, -1),
				  &addr.sin_addr.s_addr);

		lua_pop(L, 1);

		msg.msg_name = &addr;
		msg.msg_namelen = sizeof(addr);
	}
	lua_pop(L, 1);

	if (lua_istable(L, 3)) {
		buffer = kmalloc(size, GFP_KERNEL);
		if (buffer == NULL)
			luaL_error(L, "Buffer alloc fail.");
		for (i = 0; i < size; i++) {
			lua_rawgeti(L, 2, i + 1);
			buffer[i] = lua_tointeger(L, -1);
			lua_pop(L, 1);
		}
	}

	vec.iov_base = buffer;
	vec.iov_len = size;

	if ((err = kernel_sendmsg(s, &msg, &vec, 1, size)) < 0) {
		if (lua_istable(L, 3))
			kfree(buffer);
		luaL_error(L, "Socket sendmsg error: %d", err);
	}
	kfree(buffer);
	lua_pushinteger(L, err);

	return 1;
}
int luasocket_recvmsg(lua_State *L)
{
	int i;
	int err;
	size_t size = 0;
	unsigned int flags;
	struct msghdr msg;
	struct kvec vec;
	struct sockaddr_in addr;
	char tmp[sizeof "255.255.255.255"];
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	char *buffer = NULL;

	luaL_checktype(L, 2, LUA_TTABLE);

	if (IS_ENABLED(CONFIG_LUADATA)) {
		if ((buffer = ldata_topointer(L, 3, &size)) == NULL)
			flags = luaL_optnumber(L, 3, 0);
		else
			flags = luaL_optnumber(L, 4, 0);
	} else
		flags = luaL_optnumber(L, 3, 0);

	// read msghdr
	memset(&msg, 0, sizeof(msg));

	if (lua_getfield(L, 2, "name") == LUA_TTABLE) {
		addr.sin_family = s->sk->sk_family;
		addr.sin_port =
		    htons((u_short) socket_optfieldinteger(L, -1, "port", 0));

		if (lua_getfield(L, -1, "addr") == LUA_TSTRING)
			inet_pton(s->sk->sk_family, lua_tostring(L, -1),
				  &addr.sin_addr.s_addr);

		lua_pop(L, 1);

		msg.msg_name = &addr;
		msg.msg_namelen = sizeof(addr);
	}
	lua_pop(L, 1);

	if (buffer == NULL) {
		if (lua_getfield(L, 2, "iov_len") == LUA_TNUMBER) {
			size = lua_tointeger(L, -1);
			luaL_argcheck(
			    L, size > 0 && size <= LUA_SOCKET_MAXBUFFER, 2,
			    "size must be positive number and less than "
			    "maximum size");
			buffer = kmalloc(size, GFP_KERNEL);
			if (buffer == NULL)
				luaL_error(L, "Buffer alloc fail.");
		} else
			luaL_argerror(L, 2, "'iov_len' can not be empty");
		lua_pop(L, 1);
	}

	vec.iov_base = buffer;
	vec.iov_len = size;

	if ((err = kernel_recvmsg(s, &msg, &vec, 1, size, flags)) < 0) {
		if (!lua_isuserdata(L, 3))
			kfree(buffer);
		luaL_error(L, "Socket recvmsg error: %d", err);
	}

	if (!lua_isuserdata(L, 3)) {
		size = err;
		lua_createtable(L, size, 0);
		for (i = 0; i < size; i++) {
			lua_pushinteger(L, buffer[i]);
			lua_rawseti(L, -2, i + 1);
		}
		kfree(buffer);
	} else
		lua_pushvalue(L, 3);

	// return size
	lua_pushinteger(L, err);

	// write back msghdr
	lua_pushinteger(L, vec.iov_len);
	lua_setfield(L, 2, "iov_len");
	lua_pushinteger(L, msg.msg_flags);
	lua_setfield(L, 2, "flags");
	lua_createtable(L, 0, 2);
	lua_pushstring(
	    L, inet_ntop(addr.sin_family, &addr.sin_addr, tmp, sizeof tmp));
	lua_setfield(L, -2, "addr");
	lua_pushinteger(L, ntohs(addr.sin_port));
	lua_setfield(L, -2, "port");
	lua_setfield(L, 2, "name");
	lua_pushvalue(L, 2);

	return 3;
}

int luasocket_getsockname(lua_State *L)
{
	int err;
	int addrlen;
	struct sockaddr_in addr;
	char tmp[sizeof "255.255.255.255"];
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);

	if ((err = kernel_getsockname(s, (struct sockaddr *) &addr, &addrlen)) <
	    0)
		luaL_error(L, "Socket getsockname error: %d", err);

	BUG_ON(addr.sin_family != AF_INET);

	lua_pushstring(
	    L, inet_ntop(addr.sin_family, &addr.sin_addr, tmp, sizeof tmp));
	lua_pushinteger(L, ntohs(addr.sin_port));

	return 2;
}

int luasocket_getpeername(lua_State *L)
{
	int err;
	int addrlen;
	struct sockaddr_in addr;
	char tmp[sizeof "255.255.255.255"];
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);

	if ((err = kernel_getpeername(s, (struct sockaddr *) &addr, &addrlen)) <
	    0)
		luaL_error(L, "Socket getpeername error: %d", err);

	BUG_ON(addr.sin_family != AF_INET);

	lua_pushstring(
	    L, inet_ntop(addr.sin_family, &addr.sin_addr, tmp, sizeof tmp));
	lua_pushinteger(L, ntohs(addr.sin_port));

	return 2;
}

int luasocket_getsockopt(lua_State *L)
{
	int err;
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	int level = socket_tolevel(L, 2);
	int option = socket_tooption(L, 3, level);
	int optval;
	int optlen = sizeof optval;

	// TODO: add more optval support
	if ((err = kernel_getsockopt(s, level, option, (char *) &optval,
				     &optlen)) < 0)
		luaL_error(L, "Socket getsockopt error: %d", err);

	lua_pushinteger(L, optval);

	return 1;
}

int luasocket_setsockopt(lua_State *L)
{
	int err;
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	int level = socket_tolevel(L, 2);
	int option = socket_tooption(L, 3, level);
	int optval = luaL_checkinteger(L, 4);

	// TODO: add more optval support
	if ((err = kernel_setsockopt(s, level, option, (char *) &optval,
				     sizeof optval)) < 0)
		luaL_error(L, "Socket setsockopt error: %d", err);

	return 0;
}

int luasocket_close(lua_State *L)
{
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);

	sock_release(s);

	return 0;
}

static const struct luaL_Reg libluasocket_methods[] = {
    {"bind", luasocket_bind},
    {"listen", luasocket_listen},
    {"accept", luasocket_accept},
    {"connect", luasocket_connect},
    {"sendmsg", luasocket_sendmsg},
    {"recvmsg", luasocket_recvmsg},
    {"getsockname", luasocket_getsockname},
    {"getpeername", luasocket_getpeername},
    {"getsockopt", luasocket_getsockopt},
    {"setsockopt", luasocket_setsockopt},
    {"close", luasocket_close},
    {"__gc", luasocket_close},
    {NULL, NULL} /* sentinel */
};

static const struct luaL_Reg libluasocket_funtions[] = {
    {"new", luasocket}, {NULL, NULL} /* sentinel */
};

int luaopen_libsocket(lua_State *L)
{
	if (IS_ENABLED(CONFIG_LUADATA))
		luaL_requiref(L, "data", luaopen_data, 1);

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

	/* Set the methods to the metatable that should be accessed via
	 * object:func
	 */
	luaL_setfuncs(L, libluasocket_methods, 0);

	/* Register the object.func functions into the table that is at the top
	 * of the stack. */
	luaL_newlib(L, libluasocket_funtions);
	return 1;
}