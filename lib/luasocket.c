/*
* Copyright (c) 2023 ring-0 Ltda.
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

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/module.h>
#include <linux/string.h>
#include <linux/net.h>
#include <linux/version.h>
#include <net/sock.h>
#if (LINUX_VERSION_CODE <= KERNEL_VERSION(6, 1, 0))
#include <linux/l2tp.h>
#endif

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

#define luasocket_tryret(L, ret, op, ...)			\
do {								\
	if ((ret = op(__VA_ARGS__)) < 0)			\
		luaL_error(L, #op " has failed (%d)", -ret);	\
} while(0)

#define luasocket_try(L, op, ...)				\
do {								\
	int ret;						\
	luasocket_tryret(L, ret, op, __VA_ARGS__);		\
} while(0)

#define luasocket_msgaddr(msg, addr)		\
do {						\
	msg.msg_namelen = sizeof(addr);		\
	msg.msg_name = &addr;			\
} while(0)

#define LUASOCKET_SOCKADDR(addr)	(struct sockaddr *)&addr, sizeof(addr)

#define LUASOCKET_ADDRMAX		(sizeof(struct sockaddr_ll)) /* AF_PACKET */
#define LUASOCKET_ADDRLEN		(LUASOCKET_ADDRMAX - sizeof(unsigned short))
typedef struct luasocket_addr_s {
	unsigned short family;
	unsigned char data[LUASOCKET_ADDRLEN];
} luasocket_addr_t;

static int luasocket_new(lua_State *L);
static int luasocket_accept(lua_State *L);

static void luasocket_checkaddr(lua_State *L, struct socket *socket, luasocket_addr_t *addr, int ix)
{
	addr->family = socket->sk->sk_family;
	if (addr->family == AF_INET) {
		struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
		addr_in->sin_addr.s_addr = htonl((u32)luaL_checkinteger(L, ix));
		addr_in->sin_port = htons((u16)luaL_checkinteger(L, ix + 1));
	}
	else {
		size_t len;
		const char *addr_data = luaL_checklstring(L, ix, &len);
		memcpy(addr->data, addr_data, min(LUASOCKET_ADDRLEN, len));
	}
}

static int luasocket_pushaddr(lua_State *L, struct sockaddr *addr)
{
	int n;
	if (addr->sa_family == AF_INET) {
		struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
		lua_pushinteger(L, (lua_Integer)ntohl(addr_in->sin_addr.s_addr));
		lua_pushinteger(L, (lua_Integer)ntohs(addr_in->sin_port));
		n = 2;
	}
	else {
		const char *addr_data = addr->sa_data;
		lua_pushlstring(L, addr_data, sizeof(addr->sa_data));
		n = 1;
	}
	return n;
}

LUNATIK_OBJECTCHECKER(luasocket_checkpsocket, struct socket **);

#define luasocket_checksocket(L, i)	(*luasocket_checkpsocket((L), (i)))

static int luasocket_send(lua_State *L)
{
	struct socket *socket = luasocket_checksocket(L, 1);
	size_t len;
	struct kvec vec;
	struct msghdr msg;
	int nargs = lua_gettop(L);
	int ret;

	memset(&msg, 0, sizeof(msg));

	vec.iov_base = (void *)luaL_checklstring(L, 2, &len);
	vec.iov_len = len;

	if (unlikely(nargs >= 3)) {
		luasocket_addr_t addr;
		luasocket_checkaddr(L, socket, &addr, 3);
		luasocket_msgaddr(msg, addr);
	}

	luasocket_tryret(L, ret, kernel_sendmsg, socket, &msg, &vec, 1, len);
	lua_pushinteger(L, ret);
	return 1;
}

static int luasocket_receive(lua_State *L)
{
	struct socket *socket = luasocket_checksocket(L, 1);
	size_t len = (size_t)luaL_checkinteger(L, 2);
	luaL_Buffer B;
	struct kvec vec;
	struct msghdr msg;
	struct sockaddr addr;
	int flags = luaL_optinteger(L, 3, 0);
	int from = lua_toboolean(L, 4);
	int ret;

	memset(&msg, 0, sizeof(msg));

	vec.iov_base = (void *)luaL_buffinitsize(L, &B, len);
	vec.iov_len = len;

	if (unlikely(from))
		luasocket_msgaddr(msg, addr);

	luasocket_tryret(L, ret, kernel_recvmsg, socket, &msg, &vec, 1, len, flags);
	luaL_pushresultsize(&B, ret);

	return unlikely(from) ? luasocket_pushaddr(L, (struct sockaddr *)msg.msg_name) + 1 : 1;
}

static int luasocket_bind(lua_State *L)
{
	struct socket *socket = luasocket_checksocket(L, 1);
	luasocket_addr_t addr;

	luasocket_checkaddr(L, socket, &addr, 2);
	luasocket_try(L, kernel_bind, socket, LUASOCKET_SOCKADDR(addr));
	return 0;
}

static int luasocket_listen(lua_State *L)
{
	struct socket *socket = luasocket_checksocket(L, 1);
	int backlog = luaL_optinteger(L, 2, SOMAXCONN);

	luasocket_try(L, kernel_listen, socket, backlog);
	return 0;
}

static int luasocket_connect(lua_State *L)
{
	struct socket *socket = luasocket_checksocket(L, 1);
	luasocket_addr_t addr;
	int nargs = lua_gettop(L);
	int flags;

	luasocket_checkaddr(L, socket, &addr, 2);
	flags = luaL_optinteger(L, nargs, 0);

	luasocket_try(L, kernel_connect, socket, LUASOCKET_SOCKADDR(addr), flags);
	return 0;
}

#define LUASOCKET_NEWGETTER(what) 				\
static int luasocket_get##what(lua_State *L)			\
{								\
	struct socket *socket = luasocket_checksocket(L, 1);	\
	struct sockaddr addr;					\
	luasocket_try(L, kernel_get##what, socket, &addr);	\
	return luasocket_pushaddr(L, &addr);			\
}

LUASOCKET_NEWGETTER(sockname);
LUASOCKET_NEWGETTER(peername);

static void luasocket_release(void *private)
{
	sock_release(*(struct socket **)(private));
}

static const luaL_Reg luasocket_lib[] = {
	{"new", luasocket_new},
	{"close", lunatik_closeobject},
	{"send", luasocket_send},
	{"receive", luasocket_receive},
	{"bind", luasocket_bind},
	{"listen", luasocket_listen},
	{"accept", luasocket_accept},
	{"connect", luasocket_connect},
	{"getsockname", luasocket_getsockname},
	{"getpeername", luasocket_getpeername},
	{NULL, NULL}
};

static const luaL_Reg luasocket_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
	{"__index", lunatik_monitorobject},
	{"close", lunatik_closeobject},
	{"send", luasocket_send},
	{"receive", luasocket_receive},
	{"bind", luasocket_bind},
	{"listen", luasocket_listen},
	{"accept", luasocket_accept},
	{"connect", luasocket_connect},
	{"getsockname", luasocket_getsockname},
	{"getpeername", luasocket_getpeername},
	{NULL, NULL}
};

static const lunatik_reg_t luasocket_af[] = {
	{"UNSPEC", AF_UNSPEC},
	{"UNIX", AF_UNIX},
	{"LOCAL", AF_LOCAL},
	{"INET", AF_INET},
	{"AX25", AF_AX25},
	{"IPX", AF_IPX},
	{"APPLETALK", AF_APPLETALK},
	{"NETROM", AF_NETROM},
	{"BRIDGE", AF_BRIDGE},
	{"ATMPVC", AF_ATMPVC},
	{"X25", AF_X25},
	{"INET6", AF_INET6},
	{"ROSE", AF_ROSE},
	{"DECnet", AF_DECnet},
	{"NETBEUI", AF_NETBEUI},
	{"SECURITY", AF_SECURITY},
	{"KEY", AF_KEY},
	{"NETLINK", AF_NETLINK},
	{"ROUTE", AF_ROUTE},
	{"PACKET", AF_PACKET},
	{"ASH", AF_ASH},
	{"ECONET", AF_ECONET},
	{"ATMSVC", AF_ATMSVC},
	{"RDS", AF_RDS},
	{"SNA", AF_SNA},
	{"IRDA", AF_IRDA},
	{"PPPOX", AF_PPPOX},
	{"WANPIPE", AF_WANPIPE},
	{"LLC", AF_LLC},
	{"IB", AF_IB},
	{"MPLS", AF_MPLS},
	{"CAN", AF_CAN},
	{"TIPC", AF_TIPC},
	{"BLUETOOTH", AF_BLUETOOTH},
	{"IUCV", AF_IUCV},
	{"RXRPC", AF_RXRPC},
	{"ISDN", AF_ISDN},
	{"PHONET", AF_PHONET},
	{"IEEE802154", AF_IEEE802154},
	{"CAIF", AF_CAIF},
	{"ALG", AF_ALG},
	{"NFC", AF_NFC},
	{"VSOCK", AF_VSOCK},
	{"KCM", AF_KCM},
	{"QIPCRTR", AF_QIPCRTR},
	{"SMC", AF_SMC},
	{"XDP", AF_XDP},
	{"MCTP", AF_MCTP},
	{"MAX", AF_MAX},
	{NULL, 0}
};

static const lunatik_reg_t luasocket_msg[] = {
	{"OOB", MSG_OOB},
	{"PEEK", MSG_PEEK},
	{"DONTROUTE", MSG_DONTROUTE},
	{"TRYHARD", MSG_TRYHARD},
	{"CTRUNC", MSG_CTRUNC},
	{"PROBE", MSG_PROBE},
	{"TRUNC", MSG_TRUNC},
	{"DONTWAIT", MSG_DONTWAIT},
	{"EOR", MSG_EOR},
	{"WAITALL", MSG_WAITALL},
	{"FIN", MSG_FIN},
	{"SYN", MSG_SYN},
	{"CONFIRM", MSG_CONFIRM},
	{"RST", MSG_RST},
	{"ERRQUEUE", MSG_ERRQUEUE},
	{"NOSIGNAL", MSG_NOSIGNAL},
	{"MORE", MSG_MORE},
	{"WAITFORONE", MSG_WAITFORONE},
	{"SENDPAGE_NOPOLICY", MSG_SENDPAGE_NOPOLICY},
	{"SENDPAGE_NOTLAST", MSG_SENDPAGE_NOTLAST},
	{"BATCH", MSG_BATCH},
	{"EOF", MSG_EOF},
	{"NO_SHARED_FRAGS", MSG_NO_SHARED_FRAGS},
	{"SENDPAGE_DECRYPTED", MSG_SENDPAGE_DECRYPTED},
	{"ZEROCOPY", MSG_ZEROCOPY},
	{"FASTOPEN", MSG_FASTOPEN},
	{"CMSG_CLOEXEC", MSG_CMSG_CLOEXEC},
	{NULL, 0}
};

static const lunatik_reg_t luasocket_sock[] = {
	{"STREAM", SOCK_STREAM},
	{"DGRAM", SOCK_DGRAM},
	{"RAW", SOCK_RAW},
	{"RDM", SOCK_RDM},
	{"SEQPACKET", SOCK_SEQPACKET},
	{"DCCP", SOCK_DCCP},
	{"PACKET", SOCK_PACKET},
	{"CLOEXEC", SOCK_CLOEXEC},
	{"NONBLOCK", SOCK_NONBLOCK},
	{NULL, 0}
};

static const lunatik_reg_t luasocket_ipproto[] = {
	{"IP", IPPROTO_IP},
	{"ICMP", IPPROTO_ICMP},
	{"IGMP", IPPROTO_IGMP},
	{"IPIP", IPPROTO_IPIP},
	{"TCP", IPPROTO_TCP},
	{"EGP", IPPROTO_EGP},
	{"PUP", IPPROTO_PUP},
	{"UDP", IPPROTO_UDP},
	{"IDP", IPPROTO_IDP},
	{"TP", IPPROTO_TP},
	{"DCCP", IPPROTO_DCCP},
	{"IPV6", IPPROTO_IPV6},
	{"RSVP", IPPROTO_RSVP},
	{"GRE", IPPROTO_GRE},
	{"ESP", IPPROTO_ESP},
	{"AH", IPPROTO_AH},
	{"MTP", IPPROTO_MTP},
	{"BEETPH", IPPROTO_BEETPH},
	{"ENCAP", IPPROTO_ENCAP},
	{"PIM", IPPROTO_PIM},
	{"COMP", IPPROTO_COMP},
	{"L2TP", IPPROTO_L2TP},
	{"SCTP", IPPROTO_SCTP},
	{"UDPLITE", IPPROTO_UDPLITE},
	{"MPLS", IPPROTO_MPLS},
	{"ETHERNET", IPPROTO_ETHERNET},
	{"RAW", IPPROTO_RAW},
	{"MPTCP", IPPROTO_MPTCP},
	{NULL, 0}
};

static const lunatik_namespace_t luasocket_flags[] = {
	{"af", luasocket_af},
	{"msg", luasocket_msg},
	{"sock", luasocket_sock},
	{"ipproto", luasocket_ipproto},
	{NULL, NULL}
};

static const lunatik_class_t luasocket_class = {
	.name = "socket",
	.methods = luasocket_mt,
	.release = luasocket_release,
	.sleep = true,
};

#define luasocket_newsocket(L)		(lunatik_newobject((L), &luasocket_class, sizeof(struct socket *)))
#define luasocket_psocket(object)	((struct socket **)object->private)

static int luasocket_accept(lua_State *L)
{
	struct socket *socket = luasocket_checksocket(L, 1);
	int flags = luaL_optinteger(L, 2, 0);
	lunatik_object_t *object = luasocket_newsocket(L);

	luasocket_try(L, kernel_accept, socket, luasocket_psocket(object), flags);
	return 1; /* object */
}

static int luasocket_new(lua_State *L)
{
	int family = luaL_checkinteger(L, 1);
	int type = luaL_checkinteger(L, 2);
	int proto = luaL_checkinteger(L, 3);
	lunatik_object_t *object = luasocket_newsocket(L);

	luasocket_try(L, sock_create, family, type, proto, luasocket_psocket(object));
	return 1; /* object */
}

LUNATIK_NEWLIB(socket, luasocket_lib, &luasocket_class, luasocket_flags);

static int __init luasocket_init(void)
{
	return 0;
}

static void __exit luasocket_exit(void)
{
}

module_init(luasocket_init);
module_exit(luasocket_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

