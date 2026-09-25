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
#include <linux/netlink.h>
#include <linux/ipv6.h>
#include <net/sock.h>
#include <net/inet_sock.h>

#include <lunatik.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 7, 0)
typedef int (*luasocket_setter_t)(struct socket *, int, int, sockptr_t, unsigned int);
#endif

#define luasocket_msgaddr(msg, addr, size)	\
do {						\
	msg.msg_namelen = size;			\
	msg.msg_name = &addr;			\
} while (0)

#define LUASOCKET_ADDRMAX	(sizeof_field(struct sockaddr_storage, __data))

static int luasocket_lnew(lua_State *L);
static int luasocket_accept(lua_State *L);

#define LUASOCKET_ISUNIX(family)	((family) == AF_UNIX || (family) == AF_LOCAL)
#define luasocket_family(socket)	((socket)->sk->sk_family)

/* these families spell an address with two arguments, the rest with one */
#define luasocket_ispair(family)	((family) == AF_INET || (family) == AF_PACKET || (family) == AF_NETLINK)

static size_t luasocket_checkaddr(lua_State *L, struct socket *socket, struct sockaddr_storage *addr, int ix)
{
	memset(addr, 0, sizeof(*addr));
	addr->ss_family = luasocket_family(socket);
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
		luaL_argcheck(L, len <= UNIX_PATH_MAX, ix, "out of bounds");
		memcpy(addr_un->sun_path, addr_data, len);
		return offsetof(struct sockaddr_un, sun_path) + len;
	}
#endif
	else if (addr->ss_family == AF_PACKET) {
		struct sockaddr_ll *addr_ll = (struct sockaddr_ll *)addr;
		addr_ll->sll_protocol = htons((u16)lunatik_checkinteger(L, ix, 0, U16_MAX));
		addr_ll->sll_ifindex = (int)lunatik_checkinteger(L, ix + 1, 0, INT_MAX);;
		return sizeof(struct sockaddr_ll);
	}
	else if (addr->ss_family == AF_NETLINK) {
		struct sockaddr_nl *addr_nl = (struct sockaddr_nl *)addr;
		addr_nl->nl_pid = (u32)luaL_optinteger(L, ix, 0);
		addr_nl->nl_groups = (u32)luaL_optinteger(L, ix + 1, 0);
		return sizeof(struct sockaddr_nl);
	}
	else {
		size_t len;
		const char *addr_data = luaL_checklstring(L, ix, &len);
		luaL_argcheck(L, len <= LUASOCKET_ADDRMAX, ix, "out of bounds");
		memcpy(addr->__data, addr_data, len);
		return sizeof(struct sockaddr_storage);
	}
}

#define luasocket_ispathname(addr_un, len)	((len) > 0 && (addr_un)->sun_path[0] != '\0')

static int luasocket_pushaddr(lua_State *L, struct sockaddr_storage *addr, size_t size)
{
	int n;
	if (size < sizeof(addr->ss_family))
		return 0;

	if (addr->ss_family == AF_INET) {
		struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
		lua_pushinteger(L, (lua_Integer)ntohl(addr_in->sin_addr.s_addr));
		lua_pushinteger(L, (lua_Integer)ntohs(addr_in->sin_port));
		n = 2;
	}
#ifdef CONFIG_UNIX
	else if (LUASOCKET_ISUNIX(addr->ss_family)) {
		struct sockaddr_un *addr_un = (struct sockaddr_un *)addr;
		size_t len = size - offsetof(struct sockaddr_un, sun_path);
		/* the length a pathname reports counts its terminator */
		lua_pushlstring(L, addr_un->sun_path, luasocket_ispathname(addr_un, len) ? len - 1 : len);
		n = 1;
	}
#endif
	else if (addr->ss_family == AF_NETLINK) {
		struct sockaddr_nl *addr_nl = (struct sockaddr_nl *)addr;
		lua_pushinteger(L, (lua_Integer)addr_nl->nl_pid);
		lua_pushinteger(L, (lua_Integer)addr_nl->nl_groups);
		n = 2;
	}
	else {
		lua_pushlstring(L, (const char *)addr->__data, size - sizeof(addr->ss_family));
		n = 1;
	}
	return n;
}

static const lunatik_class_t luasocket_class;

LUNATIK_PRIVATECHECKER(luasocket_check, struct socket *, &luasocket_class);

#define luasocket_setmsg(m)		memset(&(m), 0, sizeof(m))

static inline void luasocket_checkrtnl(lua_State *L, struct socket *socket)
{
	if (luasocket_family(socket) == AF_NETLINK) /* the kernel runs a request, and a dump, on this task */
		lunatik_checkrtnl(L);
}

static inline bool luasocket_takesrtnl(struct socket *socket)
{
	struct sock *sk = socket->sk;

	switch (luasocket_family(socket)) {
	case AF_INET6:
		if (IS_ENABLED(CONFIG_IPV6) &&
			(rcu_access_pointer(inet6_sk(sk)->ipv6_mc_list) != NULL || inet6_sk(sk)->ipv6_ac_list != NULL))
			return true;
		fallthrough; /* inet6_release ends in inet_release: an IPv4 group joined through SOL_IP */
	case AF_INET:
		return rcu_access_pointer(inet_sk(sk)->mc_list) != NULL;
	case AF_PACKET:
		return true; /* its membership list is private to net/packet */
	case AF_NETLINK:
		return sk->sk_protocol == NETLINK_GENERIC; /* its release walks the families under cb_lock */
	}
	return false;
}

/* only a generic netlink socket bound to a group runs genl_bind, which walks the families under cb_lock */
#define luasocket_isgenlgroup(socket, addr)	\
	(luasocket_family(socket) == AF_NETLINK && (socket)->sk->sk_protocol == NETLINK_GENERIC && \
	((struct sockaddr_nl *)(addr))->nl_groups != 0)

/***
* A kernel socket, returned by `socket.new()`.
* @type socket
*/

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
* @raise Error if the send operation fails or if address parameters are incorrect for the socket type,
*   or on a netlink socket under RTNL, as from a netdevice callback.
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

	luasocket_checkrtnl(L, socket);
	luasocket_setmsg(msg);

	vec.iov_base = (void *)luaL_checklstring(L, 2, &len);
	vec.iov_len = len;

	/* netlink needs an explicit destination to set NETLINK_SKB_DST */
	if (unlikely(nargs >= 3) || luasocket_family(socket) == AF_NETLINK) {
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
* @treturn[opt] integer|string addr If `from` is true and the protocol named a sender, its address.
*   TCP names none, and neither does an `AF_UNIX` peer that never bound; nothing follows the message
*   then.
*   - For `AF_INET`: An integer representing the IPv4 address (can be converted with `net.ntoa()`).
*   - For `AF_UNIX`: The sender's name, carrying its leading NUL when the name is an abstract one.
*   - For other families: A packed string of the sender's address past the family, of the length the
*     protocol reports.
* @treturn[opt] integer port If `from` is true and the family is `AF_INET`, the sender's port number.
* @raise Error if the receive operation fails, or on a netlink socket under RTNL, as from a netdevice
*   callback.
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

	luasocket_checkrtnl(L, socket);
	luasocket_setmsg(msg);

	vec.iov_base = (void *)luaL_buffinitsize(L, &B, len);
	vec.iov_len = len;

	if (unlikely(from))
		msg.msg_name = &addr;

	lunatik_tryret(L, ret, kernel_recvmsg, socket, &msg, &vec, 1, len, flags);
	luaL_pushresultsize(&B, ret);

	/* msg_namelen is an output: zero means the protocol named no address */
	return unlikely(from) ? luasocket_pushaddr(L, &addr, msg.msg_namelen) + 1 : 1;
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
*   - `AF_UNIX`: A filesystem path, or, when its first byte is NUL (e.g. `"\0name"`), a name in the
*     abstract namespace, which is registered as the exact bytes given, so a peer of any kind reaches
*     it by the same string. The empty string asks the kernel to pick a name (autobind).
*   - Other families: A packed string directly representing parts of the family-specific address structure.
*
* @tparam[opt] integer port local port or interface index.
*   - `AF_INET`: TCP/UDP port number.
*   - `AF_PACKET`: Network interface index (e.g., from `linux.ifindex("eth0")`).
*
* @treturn nil
* @raise Error if the bind operation fails (e.g., address already in use, invalid address), or
*   "not allowed under RTNL" on a generic netlink socket bound to a group from a netdevice
*   callback: that bind takes a lock a request holds while it waits on RTNL.
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

	if (luasocket_isgenlgroup(socket, &addr))
		lunatik_checkrtnl(L);
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0))
	lunatik_try(L, kernel_bind, socket, (struct sockaddr_unsized *)&addr, size);
#else
	lunatik_try(L, kernel_bind, socket, (struct sockaddr *)&addr, size);
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
* @tparam[opt=0] integer flags file status flags: `O_NONBLOCK` makes a connect that cannot
*   complete at once raise instead of waiting for it. `linux.socket.sock.NONBLOCK` carries
*   `O_NONBLOCK` on every architecture but alpha and parisc.
* @treturn nil
* @raise Error if the connect operation fails (e.g., connection refused, host unreachable).
* @usage
*   tcp_client_sock:connect(net.aton("192.168.1.100"), 80)
*/
static int luasocket_connect(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	struct sockaddr_storage addr;
	size_t size = luasocket_checkaddr(L, socket, &addr, 2);
	int flags = luaL_optinteger(L, luasocket_ispair(luasocket_family(socket)) ? 4 : 3, 0);

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0))
	lunatik_try(L, kernel_connect, socket, (struct sockaddr_unsized *)&addr, size, flags);
#else
	lunatik_try(L, kernel_connect, socket, (struct sockaddr *)&addr, size, flags);
#endif
	return 0;
}

#define LUASOCKET_NEWGETTER(what) 						\
static int luasocket_get##what(lua_State *L)					\
{										\
	struct socket *socket = luasocket_check(L, 1);				\
	struct sockaddr_storage addr;						\
	int size;								\
	lunatik_tryret(L, size, kernel_get##what, socket,			\
		(struct sockaddr *)&addr);					\
	return luasocket_pushaddr(L, &addr, size);				\
}

/***
* Gets the local address to which the socket is bound.
*
* @function getsockname
* @treturn integer|string addr local address.
*
* - For `AF_INET`: An integer representing the IPv4 address (can be converted with `net.ntoa()`).
* - For `AF_UNIX`: The bound name, carrying its leading NUL when the name is an abstract one, and the
*   empty string when the socket is unbound.
* - For other families: A packed string of the address bytes past the family, of the length the kernel
*   reports, which for `AF_PACKET` follows the interface's hardware address length.
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
* - For `AF_UNIX`: The peer's name, carrying its leading NUL when the name is an abstract one, and the
*   empty string when the peer is unbound.
* - For other families: A packed string of the address bytes past the family, of the length the kernel
*   reports.
* @treturn[opt] integer port If the family is `AF_INET`, the peer's port number.
* @raise Error if the operation fails (e.g., socket not connected).
* @usage
*   local peer_ip_int, peer_port = connected_socket:getpeername()
*   if connected_socket.sk.sk_family == linux.socket.af.INET then print("Connected to " .. net.ntoa(peer_ip_int) .. ":" .. peer_port) end
*/
LUASOCKET_NEWGETTER(peername);

/***
* Sets a socket option.
* `SOL_SOCKET` options are handled by the network core; any other level is
* passed to the socket's protocol handler, mirroring the `setsockopt(2)`
* routing.
*
* @function setsockopt
* @tparam integer level option level (e.g., `linux.socket.sol.SOCKET`).
* @tparam integer optname option name (e.g., `linux.socket.so.RCVTIMEO_NEW`).
* @tparam integer|string value option value: an integer for the common `int`
*   payload, or a string carrying the option's packed binary payload.
* @raise Error if the operation fails, or at a level other than `SOL_SOCKET` under RTNL, as from a
*   netdevice callback.
* @usage
*   -- bound blocking receives to 500 ms (a `struct __kernel_sock_timeval`)
*   sock:setsockopt(sol.SOCKET, so.RCVTIMEO_NEW, timeval:pack(0, 500000))
*/
static int luasocket_setsockopt(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	int level = (int)luaL_checkinteger(L, 2);
	int optname = (int)luaL_checkinteger(L, 3);
	int value;
	size_t len;
	const char *optval;

	if (level != SOL_SOCKET) /* a protocol's options can take RTNL, for a multicast membership among others */
		lunatik_checkrtnl(L);

	if (lua_type(L, 4) == LUA_TSTRING)
		optval = lua_tolstring(L, 4, &len);
	else {
		value = (int)luaL_checkinteger(L, 4);
		optval = (const char *)&value;
		len = sizeof(value);
	}
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 7, 0)
	lunatik_try(L, do_sock_setsockopt, socket, false, level, optname,
		KERNEL_SOCKPTR((void *)optval), (int)len);
#else
	luasocket_setter_t setter = level == SOL_SOCKET ? sock_setsockopt : socket->ops->setsockopt;
	luaL_argcheck(L, setter != NULL, 2, "unsupported option level");
	lunatik_try(L, setter, socket, level, optname, KERNEL_SOCKPTR((void *)optval), (unsigned int)len);
#endif
	return 0;
}

static void luasocket_release(void *private)
{
	struct socket *sock = (struct socket *)private;
	kernel_sock_shutdown(sock, SHUT_RDWR);
	sock_release(sock);
}

/***
* Closes the socket.
* This shuts down the socket for both reading and writing and releases
* associated kernel resources. A to-be-closed variable holding the socket closes it the
* same way; a collected socket runs the release with no close, and no refusal.
*
* @function close
* @treturn nil
* @raise "not allowed under RTNL" from a netdevice callback, in whatever runtime or coroutine
*   its task runs, on a socket whose release takes RTNL, which that task holds, or a lock a
*   request holds while it waits on RTNL: an `AF_INET` or `AF_INET6` socket with a multicast or
*   anycast membership, an `AF_PACKET` socket, and a `NETLINK_GENERIC` one
*/
static int luasocket_close(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luasocket_class);

	lunatik_lock(object); /* one hold reads the membership and takes the socket: no sharer's join between */
	struct socket *socket = (struct socket *)object->private;
	if (socket != NULL && luasocket_takesrtnl(socket) && lunatik_isrtnl()) {
		lunatik_unlock(object);
		luaL_error(L, LUNATIK_ERR_RTNL);
	}
	object->private = NULL;
	lunatik_unlock(object);

	if (socket != NULL)
		luasocket_release(socket);
	return 0;
}

static const luaL_Reg luasocket_lib[] = {
	{"new", luasocket_lnew},
	{NULL, NULL}
};

static const luaL_Reg luasocket_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", luasocket_close},
	{"close", luasocket_close},
	{"send", luasocket_send},
	{"receive", luasocket_receive},
	{"bind", luasocket_bind},
	{"listen", luasocket_listen},
	{"accept", luasocket_accept},
	{"connect", luasocket_connect},
	{"setsockopt", luasocket_setsockopt},
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

#define luasocket_new(L)		(lunatik_newobject((L), &luasocket_class, 0, LUNATIK_OPT_NONE))
#define luasocket_psocket(object)	((struct socket **)&object->private)

/* a kernel socket holds no reference on its namespace, and a TCP one outlives its release with timers armed */
#if defined(LUNATIK_SK_NET_REFCNT_UPGRADE)
#define luasocket_upgrade(sk)		sk_net_refcnt_upgrade(sk)
#define luasocket_getnetbypid(pid)	get_net_ns_by_pid(pid)
#elif defined(LUNATIK_NET_PASSIVE_DEC)
/* the upgrade drops a passive reference through net_passive_dec, which is not exported: init_net only */
#define luasocket_upgrade(sk)
#define luasocket_getnetbypid(pid)	ERR_PTR(-EOPNOTSUPP)
#else
#define luasocket_getnetbypid(pid)	get_net_ns_by_pid(pid)
/* sk_net_refcnt_upgrade as net/smc/af_smc.c open-coded it before v6.14 */
static inline void luasocket_upgrade(struct sock *sk)
{
	struct net *net = sock_net(sk);

	__netns_tracker_free(net, &sk->ns_tracker, false);
	sk->sk_net_refcnt = 1;
	get_net_track(net, &sk->ns_tracker, GFP_KERNEL);
	sock_inuse_add(net, 1);
}
#endif

#define LUASOCKET_PID_NONE	0

#define luasocket_getnet(pid)	\
	((pid) == LUASOCKET_PID_NONE ? get_net(&init_net) : luasocket_getnetbypid(pid))

/***
* Accepts a connection on a listening socket.
* This function is used with connection-oriented sockets (e.g., `SOCK_STREAM`)
* that have been put into the listening state by `sock:listen()`.
*
* @function accept
* @tparam socket self listening socket object.
* @tparam[opt=0] integer flags file status flags: `O_NONBLOCK` makes the call raise when no
*   connection is pending instead of waiting for one. `linux.socket.sock.NONBLOCK` carries
*   `O_NONBLOCK` on every architecture but alpha and parisc.
* @treturn socket A new socket object representing the accepted connection.
* @raise Error if the accept operation fails.
*/
static int luasocket_accept(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	int flags = luaL_optinteger(L, 2, 0);
	lunatik_object_t *object = luasocket_new(L);

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
*   (e.g., `byteorder.hton16(0x0003)` for `ETH_P_ALL`).
* @tparam[opt] integer pid a task whose network namespace the socket is created in, instead of the
*   initial one. The pid is resolved in the pid namespace of the task making the call: the `lunatik`
*   process for a script's body, the initial one for a kernel thread. The socket holds its network
*   namespace until the kernel frees the socket, which for a TCP connection still shutting down comes
*   after its close, so the namespace outlives the task. The rest of Lunatik (`linux.ifindex`,
*   `netfilter`) keeps to the initial network namespace.
* @treturn socket A new socket object. A socket a netdevice callback may collect is closed by the
*   script first, not dropped: its release cannot refuse where the collector drops it.
* @raise Error if socket creation fails, `ESRCH` if no task has that pid, or `EOPNOTSUPP` on a kernel
*   whose sockets cannot hold a namespace of their own.
* @usage
*   -- TCP/IPv4 socket
*   local tcp_sock = socket.new(linux.socket.af.INET, linux.socket.sock.STREAM, linux.socket.ipproto.TCP)
*
*   -- rtnetlink socket in the network namespace of the task 1234
*   local rtnl = socket.new(linux.socket.af.NETLINK, linux.socket.sock.RAW, linux.netlink.proto.ROUTE, 1234)
* @see linux.socket.af
* @see linux.socket.sock
* @see linux.socket.ipproto
* @within socket
*/
static int luasocket_lnew(lua_State *L)
{
	int family = luaL_checkinteger(L, 1);
	int type = luaL_checkinteger(L, 2);
	int proto = luaL_checkinteger(L, 3);
	pid_t pid = lua_isnoneornil(L, 4) ? LUASOCKET_PID_NONE : (pid_t)lunatik_checkinteger(L, 4, 1, PID_MAX_LIMIT);
	lunatik_object_t *object = luasocket_new(L);
	struct socket **psocket = luasocket_psocket(object);
	struct net *net = luasocket_getnet(pid);
	int ret;

	if (IS_ERR(net))
		lunatik_throw(L, PTR_ERR(net));

	if ((ret = sock_create_kern(net, family, type, proto, psocket)) < 0) {
		put_net(net);
		lunatik_throw(L, ret);
	}
	luasocket_upgrade((*psocket)->sk);
	put_net(net);
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

