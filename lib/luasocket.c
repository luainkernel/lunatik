/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface for kernel networking sockets.
* This library provides support for creating and managing various types of
* sockets within the Linux kernel, enabling network communication directly
* from Lua scripts running in kernel space. It is inspired by
* [Chengzhi Tan](https://github.com/tcz717)'s
* [GSoC project](https://summerofcode.withgoogle.com/archive/2018/projects/5993341447569408).
*
* It allows operations such as creating sockets, binding, listening, connecting,
* sending, and receiving data. The library also exposes constants for address
* families, socket types, IP protocols, and message flags.
*
* For higher-level IPv4 TCP/UDP socket operations with string-based IP addresses
* (e.g., "127.0.0.1"), consider using the `socket.inet` library.
*
* @module socket
* @see socket.inet
*/
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/version.h>
#include <linux/string.h>
#include <linux/net.h>
#include <linux/un.h>
#include <net/sock.h>
#if (LINUX_VERSION_CODE <= KERNEL_VERSION(6, 1, 0))
#include <linux/l2tp.h>
#endif

#include <lunatik.h>

#define luasocket_msgaddr(msg, addr, size)	\
do {						\
	msg.msg_namelen = size;			\
	msg.msg_name = &addr;			\
} while (0)

#define LUASOCKET_ADDRMAX	(sizeof_field(struct sockaddr_storage, __data))

static int luasocket_new(lua_State *L);
static int luasocket_accept(lua_State *L);

#define LUASOCKET_ISUNIX(family)	((family) == AF_UNIX || (family) == AF_LOCAL)

static size_t luasocket_checkaddr(lua_State *L, struct socket *socket, struct sockaddr_storage *addr, int ix)
{
	addr->ss_family = socket->sk->sk_family;
	if (addr->ss_family == AF_INET) {
		struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
		addr_in->sin_addr.s_addr = htonl((u32)luaL_checkinteger(L, ix));
		addr_in->sin_port = htons((u16)lunatik_checkinteger(L, ix + 1, 0, U16_MAX));
		return sizeof(struct sockaddr_in);
	}
#ifdef CONFIG_UNIX
	else if (LUASOCKET_ISUNIX(addr->ss_family)) {
		size_t len;
		struct sockaddr_un *addr_un = (struct sockaddr_un *)addr;
		const char *addr_data = luaL_checklstring(L, ix, &len);
		luaL_argcheck(L, len + 1 <= UNIX_PATH_MAX, ix, "out of bounds");
		strncpy(addr_un->sun_path, addr_data, len);
		addr_un->sun_path[len] = '\0';
		return sizeof(struct sockaddr_un);
	}
#endif
	else if (addr->ss_family == AF_PACKET) {
		struct sockaddr_ll *addr_ll = (struct sockaddr_ll *)addr;
		addr_ll->sll_protocol = htons((u16)lunatik_checkinteger(L, ix, 0, U16_MAX));
		addr_ll->sll_ifindex = (int)lunatik_checkinteger(L, ix + 1, 0, INT_MAX);;
		return sizeof(struct sockaddr_ll);
	}
	else {
		size_t len;
		const char *addr_data = luaL_checklstring(L, ix, &len);
		luaL_argcheck(L, len <= LUASOCKET_ADDRMAX, ix, "out of bounds");
		memcpy(addr->__data, addr_data, len);
		return sizeof(struct sockaddr_storage);
	}
}

static int luasocket_pushaddr(lua_State *L, struct sockaddr_storage *addr)
{
	int n;
	if (addr->ss_family == AF_INET) {
		struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
		lua_pushinteger(L, (lua_Integer)ntohl(addr_in->sin_addr.s_addr));
		lua_pushinteger(L, (lua_Integer)ntohs(addr_in->sin_port));
		n = 2;
	}
#ifdef CONFIG_UNIX
	else if (LUASOCKET_ISUNIX(addr->ss_family)) {
		struct sockaddr_un *addr_un = (struct sockaddr_un *)addr;
		lua_pushstring(L, addr_un->sun_path);
		n = 1;
	}
#endif
	else {
		lua_pushlstring(L, (const char *)addr->__data, LUASOCKET_ADDRMAX);
		n = 1;
	}
	return n;
}

LUNATIK_PRIVATECHECKER(luasocket_check, struct socket *);

#define luasocket_setmsg(m)		memset(&(m), 0, sizeof(m))

/***
* Sends a message through the socket.
*
* For connection-oriented sockets (`SOCK_STREAM`), `addr` and `port` are usually omitted
* as the connection is already established.
* For connectionless sockets (`SOCK_DGRAM`), `addr` and `port` (if applicable for the
* address family) specify the destination.
*
* @function send
* @tparam string message message to send.
* @tparam[opt] integer|string addr destination address.
*
* - For `AF_INET` (IPv4) sockets: An integer representing the IPv4 address (e.g., from `net.aton()`).
* - For other address families (e.g., `AF_PACKET`): A packed string representing the destination address
*   (e.g., MAC address for `AF_PACKET`). The exact format depends on the family.
* @tparam[opt] integer port destination port number (required if `addr` is an IPv4 address for `AF_INET`).
* @treturn integer number of bytes sent.
* @raise Error if the send operation fails or if address parameters are incorrect for the socket type.
* @usage
*   -- For a connected TCP socket:
*   local bytes_sent = tcp_conn_sock:send("Hello, server!")
*
*   -- For a UDP socket (sending to 192.168.1.100, port 1234):
*   local bytes_sent = udp_sock:send("UDP packet", net.aton("192.168.1.100"), 1234)
* @see net.aton
*/
static int luasocket_send(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	size_t len;
	struct kvec vec;
	struct msghdr msg;
	struct sockaddr_storage addr;
	int nargs = lua_gettop(L);
	int ret;

	luasocket_setmsg(msg);

	vec.iov_base = (void *)luaL_checklstring(L, 2, &len);
	vec.iov_len = len;

	if (unlikely(nargs >= 3)) {
		size_t size = luasocket_checkaddr(L, socket, &addr, 3);
		luasocket_msgaddr(msg, addr, size);
	}

	lunatik_tryret(L, ret, kernel_sendmsg, socket, &msg, &vec, 1, len);
	lua_pushinteger(L, ret);
	return 1;
}

/***
* Receives a message from the socket.
*
* @function receive
* @tparam integer length maximum number of bytes to receive.
* @tparam[opt=0] integer flags Optional message flags (e.g., `linux.socket.msg.PEEK`).
*   See the `linux.socket.msg` table for available flags. These can be OR'd together.
* @tparam[opt=false] boolean from If `true`, the function also returns the sender's address
*   and port (for `AF_INET`). This is typically used with connectionless sockets (`SOCK_DGRAM`).
* @treturn string received message (as a string of bytes).
* @treturn[opt] integer|string addr If `from` is true, the sender's address.
*   - For `AF_INET`: An integer representing the IPv4 address (can be converted with `net.ntoa()`).
*   - For other families: A packed string representing the sender's address.
* @treturn[opt] integer port If `from` is true and the family is `AF_INET`, the sender's port number.
* @raise Error if the receive operation fails.
* @usage
*   -- For a connected TCP socket:
*   local data = tcp_conn_sock:receive(1024)
*   if data then print("Received:", data) end
*
*   -- For a UDP socket, getting sender info:
*   local data, sender_ip_int, sender_port = udp_sock:receive(1500, 0, true)
*   if data then print("Received from " .. net.ntoa(sender_ip_int) .. ":" .. sender_port .. ": " .. data) end
* @see linux.socket.msg
* @see net.ntoa
*/
static int luasocket_receive(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	size_t len = (size_t)luaL_checkinteger(L, 2);
	luaL_Buffer B;
	struct kvec vec;
	struct msghdr msg;
	struct sockaddr_storage addr;
	int flags = luaL_optinteger(L, 3, 0);
	int from = lua_toboolean(L, 4);
	int ret;

	luasocket_setmsg(msg);

	vec.iov_base = (void *)luaL_buffinitsize(L, &B, len);
	vec.iov_len = len;

	if (unlikely(from))
		luasocket_msgaddr(msg, addr, sizeof(addr));

	lunatik_tryret(L, ret, kernel_recvmsg, socket, &msg, &vec, 1, len, flags);
	luaL_pushresultsize(&B, ret);

	return unlikely(from) ? luasocket_pushaddr(L, (struct sockaddr_storage *)msg.msg_name) + 1 : 1;
}

/***
* Binds the socket to a local address.
* This is typically used on the server side before calling `listen()` or on
* connectionless sockets to specify a local port/interface for receiving.
*
* @function bind
* @tparam integer|string addr local address to bind to. Interpretation depends on `socket.sk.sk_family`:
*
*   - `AF_INET` (IPv4): An integer representing the IPv4 address (e.g., from `net.aton()`).
*     Use `0` (or `net.aton("0.0.0.0")`) to bind to all available interfaces.
*     The `port` argument is also required.
*   - `AF_PACKET`: An integer representing the ethernet protocol in host byte order
*     (e.g., `0x0003` for `ETH_P_ALL`, `0x88CC` for `ETH_P_LLDP`)
*     The `port` argument is also required.
*   - Other families: A packed string directly representing parts of the family-specific address structure.
*
* @tparam[opt] integer port local port or interface index.
*   - `AF_INET`: TCP/UDP port number.
*   - `AF_PACKET`: Network interface index (e.g., from `linux.ifindex("eth0")`).
*
* @treturn nil
* @raise Error if the bind operation fails (e.g., address already in use, invalid address).
* @usage
*   -- Bind TCP/IPv4 socket to localhost, port 8080
*   tcp_server_sock:bind(net.aton("127.0.0.1"), 8080)
*
*   -- Bind AF_PACKET socket to protocol `ETH_P_LLDP` on a specific interface
*   af_packet_sock:bind(0x88CC, linux.ifindex("eth0"))
* @see net.aton
* @see linux.ifindex
*/
static int luasocket_bind(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	struct sockaddr_storage addr;
	size_t size = luasocket_checkaddr(L, socket, &addr, 2);
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 19, 0))
	lunatik_try(L, kernel_bind, socket, (struct sockaddr *)&addr, size);
#else
	lunatik_try(L, kernel_bind, socket, (struct sockaddr_unsized *)&addr, size);
#endif
	return 0;
}

/***
* Puts a connection-oriented socket into the listening state.
* This is required for server sockets (e.g., `SOCK_STREAM`) to be able to
* accept incoming connections.
*
* @function listen
* @tparam[opt] integer backlog maximum length of the queue for pending connections.
*   If omitted, a system-dependent default (e.g., `SOMAXCONN`) is used.
* @treturn nil
* @raise Error if the listen operation fails (e.g., socket not bound, invalid state).
* @usage
*   tcp_server_sock:listen(10)
*/
static int luasocket_listen(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	int backlog = luaL_optinteger(L, 2, SOMAXCONN);

	lunatik_try(L, kernel_listen, socket, backlog);
	return 0;
}

/***
* Initiates a connection on a socket.
* This is typically used by client sockets to establish a connection to a server.
* For datagram sockets, this sets the default destination address for `send` and
* the only address from which datagrams are received.
*
* @function connect
* @tparam integer|string addr destination address to connect to.
*   Interpretation depends on `socket.sk.sk_family`:
*
*   - `AF_INET` (IPv4): An integer representing the IPv4 address (e.g., from `net.aton()`).
*     The `port` argument is also required.
*   - Other families: A packed string representing the family-specific destination address.
* @tparam[opt] integer port destination port number (required and used only if the family is `AF_INET`).
* @tparam[opt=0] integer flags Optional connection flags.
* @treturn nil
* @raise Error if the connect operation fails (e.g., connection refused, host unreachable).
* @usage
*   tcp_client_sock:connect(net.aton("192.168.1.100"), 80)
*/
static int luasocket_connect(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	struct sockaddr_storage addr;
	int nargs = lua_gettop(L);
	size_t size = luasocket_checkaddr(L, socket, &addr, 2);
	int flags = luaL_optinteger(L, nargs >= 4 ? 4 : 3, 0);

#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 19, 0))
	lunatik_try(L, kernel_connect, socket, (struct sockaddr *)&addr, size, flags);
#else
	lunatik_try(L, kernel_connect, socket, (struct sockaddr_unsized *)&addr, size, flags);
#endif
	return 0;
}

#define LUASOCKET_NEWGETTER(what) 						\
static int luasocket_get##what(lua_State *L)					\
{										\
	struct socket *socket = luasocket_check(L, 1);				\
	struct sockaddr_storage addr;						\
	lunatik_try(L, kernel_get##what, socket, (struct sockaddr *)&addr);	\
	return luasocket_pushaddr(L, &addr);					\
}

/***
* Gets the local address to which the socket is bound.
*
* @function getsockname
* @treturn integer|string addr local address.
*
* - For `AF_INET`: An integer representing the IPv4 address (can be converted with `net.ntoa()`).
* - For other families: A packed string representing the local address.
* @treturn[opt] integer port If the family is `AF_INET`, the local port number.
* @raise Error if the operation fails.
* @usage
*   local local_ip_int, local_port = my_socket:getsockname()
*   if my_socket.sk.sk_family == linux.socket.af.INET then print("Bound to " .. net.ntoa(local_ip_int) .. ":" .. local_port) end
*/
LUASOCKET_NEWGETTER(sockname);

/***
* Gets the address of the peer to which the socket is connected.
* This is typically used with connection-oriented sockets after a connection
* has been established, or with connectionless sockets after `connect()` has
* been called to set a default peer.
*
* @function getpeername
* @treturn integer|string addr peer's address.
*
* - For `AF_INET`: An integer representing the IPv4 address (can be converted with `net.ntoa()`).
* - For other families: A packed string representing the peer's address.
* @treturn[opt] integer port If the family is `AF_INET`, the peer's port number.
* @raise Error if the operation fails (e.g., socket not connected).
* @usage
*   local peer_ip_int, peer_port = connected_socket:getpeername()
*   if connected_socket.sk.sk_family == linux.socket.af.INET then print("Connected to " .. net.ntoa(peer_ip_int) .. ":" .. peer_port) end
*/
LUASOCKET_NEWGETTER(peername);

/***
* Closes the socket.
* This shuts down the socket for both reading and writing and releases
* associated kernel resources.
* This method is also called automatically when the socket object is garbage collected
* or via Lua 5.4's to-be-closed mechanism.
*
* @function close
* @treturn nil
*/
static void luasocket_release(void *private)
{
	struct socket *sock = (struct socket *)private;
	kernel_sock_shutdown(sock, SHUT_RDWR);
	sock_release(sock);
}

static const luaL_Reg luasocket_lib[] = {
	{"new", luasocket_new},
	{NULL, NULL}
};

static const luaL_Reg luasocket_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", lunatik_closeobject},
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

LUNATIK_OPENER(socket);
static const lunatik_class_t luasocket_class = {
	.name = "socket",
	.methods = luasocket_mt,
	.release = luasocket_release,
	.opener = luaopen_socket,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
};

#define luasocket_newsocket(L)		(lunatik_newobject((L), &luasocket_class, 0, LUNATIK_OPT_NONE))
#define luasocket_psocket(object)	((struct socket **)&object->private)

/***
* Accepts a connection on a listening socket.
* This function is used with connection-oriented sockets (e.g., `SOCK_STREAM`)
* that have been put into the listening state by `sock:listen()`.
*
* @function accept
* @tparam socket self listening socket object.
* @tparam[opt=0] integer flags Optional flags to apply to the newly accepted socket
*   (e.g., `linux.socket.sock.NONBLOCK`, `linux.socket.sock.CLOEXEC`).
* @treturn socket A new socket object representing the accepted connection.
* @raise Error if the accept operation fails.
*/
static int luasocket_accept(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	int flags = luaL_optinteger(L, 2, 0);
	lunatik_object_t *object = luasocket_newsocket(L);

	lunatik_try(L, kernel_accept, socket, luasocket_psocket(object), flags);
	return 1; /* object */
}

/***
* Creates a new socket object.
* This function is the primary way to create a socket.
*
* @function new
* @tparam integer family address family (e.g., `linux.socket.af.INET`).
* @tparam integer type socket type (e.g., `linux.socket.sock.STREAM`).
* @tparam integer protocol protocol (e.g., `linux.socket.ipproto.TCP`).
*   For `AF_PACKET` sockets, `protocol` is typically an `ETH_P_*` value in network byte order
*   (e.g., `linux.hton16(0x0003)` for `ETH_P_ALL`).
* @treturn socket A new socket object.
* @raise Error if socket creation fails.
* @usage
*   -- TCP/IPv4 socket
*   local tcp_sock = socket.new(linux.socket.af.INET, linux.socket.sock.STREAM, linux.socket.ipproto.TCP)
* @see linux.socket.af
* @see linux.socket.sock
* @see linux.socket.ipproto
* @within socket
*/
static int luasocket_new(lua_State *L)
{
	int family = luaL_checkinteger(L, 1);
	int type = luaL_checkinteger(L, 2);
	int proto = luaL_checkinteger(L, 3);
	lunatik_object_t *object = luasocket_newsocket(L);

	lunatik_try(L, sock_create_kern, &init_net, family, type, proto, luasocket_psocket(object));
	return 1; /* object */
}

LUNATIK_CLASSES(socket, &luasocket_class);
LUNATIK_NEWLIB(socket, luasocket_lib, luasocket_classes);

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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

