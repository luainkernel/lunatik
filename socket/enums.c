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

static int socket_option(lua_State *L, int n, const char *str)
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
			return luaL_argerror(L, n, "invalid option name");
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
			return luaL_argerror(L, n, "invalid option name");
		}
	case 's':
		switch (str[1]) {
		case 0:
			return SO_SNDBUF;
		case 'f':
			return SO_SNDBUFFORCE;
		default:
			return luaL_argerror(L, n, "invalid option name");
		}
	case 't':
		return SO_TYPE;
	default:
		return luaL_argerror(L, n, "invalid option name");
	}
}

int socket_tooption(lua_State *L, int n, int level)
{
	const char *str = luaL_checkstring(L, n);
	switch (level) {
	case SOL_SOCKET:
		return socket_option(L, n, str);
	default:
		return luaL_argerror(L, n, "invalid option name");
	}
}

int socket_toflags(lua_State *L, int n)
{
	size_t i, size;
	int flags = 0;
	const char *str;

	if (lua_isnumber(L, n))
		return n;

	if (lua_isnoneornil(L, n))
		return 0;

	str = luaL_checklstring(L, n, &size);
	// \#define MSG_(\w)(\w+)\W+(\w+)
	// case '$1' /*$1$2*/: flags|=$3; break;
	for (i = 0; i < size; i++) {
		switch (str[i]) {
		// case 'O' /*OOB*/:
		// 	flags |= 1;
		// 	break;
		// case 'P' /*PEEK*/:
		// 	flags |= 2;
		// 	break;
		// case 'D' /*DONTROUTE*/:
		// 	flags |= 4;
		// 	break;
		// case 'T' /*TRYHARD*/:
		// 	flags |= 4;
		// 	break; /* Synonym for MSG_DONTROUTE for DECnet */
		// case 'C' /*CTRUNC*/:
		// 	flags |= 8;
		// 	break;
		// case 'P' /*PROBE*/:
		// 	flags |= 0x10;
		// 	break; /* Do not send. Only probe path f.e. for MTU */
		// case 'T' /*TRUNC*/:
		// 	flags |= 0x20;
		// 	break;
		case 'D' /*DONTWAIT*/:
			flags |= 0x40;
			break; /* Nonblocking io		 */
		// case 'E' /*EOR*/:
		// 	flags |= 0x80;
		// 	break; /* End of record */
		// case 'W' /*WAITALL*/:
		// 	flags |= 0x100;
		// 	break; /* Wait for a full request */
		// case 'F' /*FIN*/:
		// 	flags |= 0x200;
		// 	break;
		// case 'S' /*SYN*/:
		// 	flags |= 0x400;
		// 	break;
		// case 'C' /*CONFIRM*/:
		// 	flags |= 0x800;
		// 	break; /* Confirm path validity */
		// case 'R' /*RST*/:
		// 	flags |= 0x1000;
		// 	break;
		// case 'E' /*ERRQUEUE*/:
		// 	flags |= 0x2000;
		// 	break; /* Fetch message from error queue */
		// case 'N' /*NOSIGNAL*/:
		// 	flags |= 0x4000;
		// 	break; /* Do not generate SIGPIPE */
		// case 'M' /*MORE*/:
		// 	flags |= 0x8000;
		// 	break; /* Sender will send more */
		// case 'W' /*WAITFORONE*/:
		// 	flags |= 0x10000;
		// 	break; /* recvmmsg(): block until 1+ packets avail */
		// case 'S' /*SENDPAGE_NOTLAST*/:
		// 	flags |= 0x20000;
		// 	break; /* sendpage() internal : not the last page */
		// case 'B' /*BATCH*/:
		// 	flags |= 0x40000;
		// 	break; /* sendmmsg(): more messages coming */
		// case 'E' /*EOF*/:
		// 	flags |= MSG_FIN;
		// 	break;
		// case 'N' /*NO_SHARED_FRAGS*/:
		// 	flags |= 0x80000;
		// 	break; /* sendpage() internal : page frags are not
		// 		  shared */
		default:
			luaL_argerror(L, n, "invalid flags name");
		}
	}
	return flags;
}