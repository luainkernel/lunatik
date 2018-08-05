#include "socket.h"
#include <net/sock.h>

#ifdef CONFIG_LUADATA
#include <luadata.h>
#endif /* CONFIG_LUADATA */

#include "enums.h"

#define __GETNAME_CHANGED (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 17, 0))
#if __GETNAME_CHANGED
#define __luasocket_getpeername(socket, addr, addrlen)                         \
	(*(addrlen) = kernel_getpeername((s), (addr)))
#define __luasocket_getsockname(socket, addr, addrlen)                         \
	(*(addrlen) = kernel_getsockname((s), (addr)))
#else
#define __luasocket_getpeername(socket, addr, addrlen)                         \
	kernel_getpeername((s), (addr), (addrlen))
#define __luasocket_getsockname(socket, addr, addrlen)                         \
	kernel_getsockname((s), (addr), (addrlen))
#endif /* __GETNAME_CHANGED */

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

inline void socket_error(lua_State *L, int err)
{
	lua_pushinteger(L, err);
	lua_error(L);
}

int luasocket(lua_State *L)
{
	int err;
	sock_t sock;

	if ((err = sock_create(socket_tofamily(L, 1), socket_totype(L, 2), 0,
			       &sock)) < 0)
		socket_error(L, err);

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
	int ip;
	const int ip_type = lua_type(L, 2);
	const int port = luaL_checkinteger(L, 3);

	if (ip_type == LUA_TNUMBER)
		ip = htonl((u_long) lua_tonumber(L, 2));
	else if (ip_type == LUA_TSTRING)
		inet_pton(s->sk->sk_family, lua_tostring(L, 2), &ip);
	else
		luaL_argerror(L, 2, "IP must be number or port");

	luaL_argcheck(L, port > 0 && port <= 65535, 2,
		      "Port number out of range");

	addr.sin_family = s->sk->sk_family;
	addr.sin_port = htons((u_short) port);
	addr.sin_addr.s_addr = ip;

	if ((err = kernel_bind(s, (struct sockaddr *) &addr, sizeof(addr))) < 0)
		socket_error(L, err);

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
		socket_error(L, err);

	return 0;
}
int luasocket_accept(lua_State *L)
{
	int err;
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);
	const int flags = socket_toflags(L, 2);
	sock_t newsock;

	if ((err = kernel_accept(s, &newsock, flags)) < 0)
		socket_error(L, err);

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
	int ip;
	const int ip_type = lua_type(L, 2);
	const int port = luaL_checkinteger(L, 3);
	const int flags = luaL_optinteger(L, 4, 0);

	if (ip_type == LUA_TNUMBER)
		ip = htonl((u_long) lua_tonumber(L, 2));
	else if (ip_type == LUA_TSTRING)
		inet_pton(s->sk->sk_family, lua_tostring(L, 2), &ip);
	else
		luaL_argerror(L, 2, "IP must be number or port");

	luaL_argcheck(L, port > 0 && port <= 65535, 2,
		      "Port number out of range");

	addr.sin_family = s->sk->sk_family;
	addr.sin_port = htons((u_short) port);
	addr.sin_addr.s_addr = ip;

	if ((err = kernel_connect(s, (struct sockaddr *) &addr, sizeof(addr),
				  flags)) < 0)
		socket_error(L, err);

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
			lua_rawgeti(L, 3, i + 1);
			buffer[i] = lua_tointeger(L, -1);
			lua_pop(L, 1);
		}
	}

	vec.iov_base = buffer;
	vec.iov_len = size;

	err = kernel_sendmsg(s, &msg, &vec, 1, size);
	if (lua_istable(L, 3))
		kfree(buffer);
	if (err < 0)
		socket_error(L, err);

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
			flags = socket_toflags(L, 3);
		else
			flags = socket_toflags(L, 4);
	} else
		flags = socket_toflags(L, 3);

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
		socket_error(L, err);
	}
	size = err;

	if (!lua_isuserdata(L, 3)) {
		lua_createtable(L, size, 0);
		for (i = 0; i < size; i++) {
			lua_pushinteger(L, buffer[i]);
			lua_rawseti(L, -2, i + 1);
		}
		kfree(buffer);
	} else
		lua_pushvalue(L, 3);

	// return size
	lua_pushinteger(L, size);

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

int luasocket_send(lua_State *L)
{
	// insert empty msghdr
	lua_newtable(L);
	lua_insert(L, 2);

	luasocket_sendmsg(L);

	return 1;
}
int luasocket_recv(lua_State *L)
{
	// insert empty msghdr
	lua_newtable(L);
	lua_insert(L, 2);

	luasocket_recvmsg(L);

	// pop unused msghdr result
	lua_pop(L, 1);

	return 2;
}

int luasocket_getsockname(lua_State *L)
{
	int err;
	int addrlen;
	struct sockaddr_in addr;
	char tmp[sizeof "255.255.255.255"];
	sock_t s = *(sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);

	if ((err = __luasocket_getsockname(s, (struct sockaddr *) &addr,
					   &addrlen)) < 0)
		socket_error(L, err);

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

	if ((err = __luasocket_getpeername(s, (struct sockaddr *) &addr,
					   &addrlen)) < 0)
		socket_error(L, err);

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
		socket_error(L, err);

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
		socket_error(L, err);

	return 0;
}

int luasocket_close(lua_State *L)
{
	sock_t *s = (sock_t *) luaL_checkudata(L, 1, LUA_SOCKET);

	if (*s == NULL)
		return 0;

	sock_release(*s);

	*s = NULL;

	return 0;
}

static const struct luaL_Reg libluasocket_methods[] = {
    {"bind", luasocket_bind},
    {"listen", luasocket_listen},
    {"accept", luasocket_accept},
    {"connect", luasocket_connect},
    {"send", luasocket_send},
    {"recv", luasocket_recv},
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
    {"new", luasocket}, {"poll", lpoll}, {NULL, NULL} /* sentinel */
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

	luaopen_lpoll(L);

	/* Register the object.func functions into the table that is at the top
	 * of the stack. */
	luaL_newlib(L, libluasocket_funtions);
	return 1;
}