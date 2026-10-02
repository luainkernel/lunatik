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
* sending, and receiving data. The constants for address families, socket types,
* protocols, message flags and option levels and names are in `linux.socket`
* (`af`, `sock`, `ipproto`, `msg`, `sol`, `so`).
*
* An integer argument is bounded to the kernel type that takes it, an `int` unless a method
* says otherwise: one past it raises "out of bounds" instead of reaching the kernel truncated.
*
* Sockets sleep: a script creates and uses them in a process runtime, the default, or in a
* spawned thread. In a softirq or hardirq runtime, `socket.new` and `accept` raise
* `'socket': process-context class in interrupt-context runtime`.
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

#include "lualinux.h"

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
#define LUASOCKET_ISINET(family)	((family) == AF_INET || (family) == AF_INET6)
#define luasocket_family(socket)	((socket)->sk->sk_family)

/* these families spell an address with two arguments, the rest with one */
#define luasocket_ispair(family)	((family) == AF_INET || (family) == AF_PACKET || (family) == AF_NETLINK)

#define luasocket_checkethertype(L, ix)	htons((u16)lunatik_checkinteger((L), (ix), 0, U16_MAX))
#define luasocket_checkint(L, ix)	((int)lunatik_checkinteger((L), (ix), INT_MIN, INT_MAX))
#define luasocket_checku32(L, ix)	((u32)lunatik_checkinteger((L), (ix), 0, U32_MAX))

static size_t luasocket_checkaddr(lua_State *L, struct socket *socket, struct sockaddr_storage *addr, int ix)
{
	memset(addr, 0, sizeof(*addr));
	addr->ss_family = luasocket_family(socket);
	if (addr->ss_family == AF_INET) {
		struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
		addr_in->sin_addr.s_addr = htonl(luasocket_checku32(L, ix));
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
		addr_ll->sll_protocol = luasocket_checkethertype(L, ix);
		addr_ll->sll_ifindex = (int)lunatik_checkinteger(L, ix + 1, 0, INT_MAX);;
		return sizeof(struct sockaddr_ll);
	}
	else if (addr->ss_family == AF_NETLINK) {
		struct sockaddr_nl *addr_nl = (struct sockaddr_nl *)addr;
		addr_nl->nl_pid = luaL_opt(L, luasocket_checku32, ix, 0);
		addr_nl->nl_groups = luaL_opt(L, luasocket_checku32, ix + 1, 0);
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
	else if (addr->ss_family == AF_PACKET) {
		struct sockaddr_ll *addr_ll = (struct sockaddr_ll *)addr;
		lua_pushinteger(L, (lua_Integer)ntohs(addr_ll->sll_protocol));
		lua_pushinteger(L, (lua_Integer)addr_ll->sll_ifindex);
		lua_pushinteger(L, (lua_Integer)addr_ll->sll_pkttype);
		lua_pushinteger(L, (lua_Integer)addr_ll->sll_hatype);
		lua_pushlstring(L, (const char *)addr_ll->sll_addr, addr_ll->sll_halen);
		n = 5;
	}
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

/* a nonblocking flag or a timeout ends the wait with an errno that is an outcome, not a failure */
static int luasocket_pushfail(lua_State *L, int ret, bool outcome)
{
	if (!outcome)
		lunatik_throw(L, ret);
	return lunatik_pushfail(L, ret);
}

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

/* only a protocol with get_port binds a port, the one inet_num holds */
#define luasocket_isunbound(socket)	\
	(LUASOCKET_ISINET(luasocket_family(socket)) && (socket)->sk->sk_prot->get_port != NULL && \
	data_race(!inet_sk((socket)->sk)->inet_num))

/***
* A kernel socket, returned by `socket.new()`.
*
* A method that takes an address reads it the way the family the socket was created with spells it:
*
* - `AF_INET`: two integers, the IPv4 address (e.g. from `net.aton()`), within 32 bits, and the port,
*   within 16.
* - `AF_INET6`: a packed string of `struct sockaddr_in6` past the family: the port and the flow
*   information in network byte order, the address, and the scope id.
* - `AF_PACKET`: two integers, the ethertype in host byte order, within 16 bits, and the interface
*   index, from 0.
* - `AF_NETLINK`: two optional integers, the port id and the multicast groups, both 0 by default and
*   within 32 bits.
* - `AF_UNIX`: a string, a filesystem path or, with a leading NUL, an abstract name.
* - Other families: a packed string of the address bytes past the family.
*
* A method that returns an address returns it the same way. An `AF_PACKET` one carries three more
* values after the interface index: the packet type (`PACKET_HOST` and the others of
* `<linux/if_packet.h>`), the hardware type (`ARPHRD_ETHER` and the others of `<linux/if_arp.h>`)
* and the hardware address, a string of the length the kernel reports: the interface's own for
* `getsockname`, the sender's for `receivefrom`.
* @type socket
*/

/***
* Sends a message through the socket.
*
* For connection-oriented sockets (`SOCK_STREAM`), `addr` and `port` are usually omitted
* as the connection is already established.
* For connectionless sockets (`SOCK_DGRAM`), `addr` and `port` (if applicable for the
* address family) specify the destination.
* A netlink socket always sends to an address, the kernel's (port id 0) when none is given.
* The call waits for room in the send buffer, with no timeout of its own, unless `setsockopt` set a
* send timeout (`linux.socket.so.SNDTIMEO_NEW`), which makes a wait it ends with nothing queued
* answer `false`. A `lunatik stop` of the spawned thread that waits ends its wait, which raises
* `ERESTARTSYS`, or `EINTR` under a send timeout, when nothing was queued.
*
* @function send
* @tparam string message message to send.
* @tparam[opt] integer|string addr destination address, as the `socket` type describes it.
*
* - For `AF_INET` (IPv4) sockets: An integer representing the IPv4 address (e.g., from `net.aton()`).
* - For `AF_PACKET`: the ethertype, in host byte order.
* - For `AF_NETLINK`: the destination port id.
* @tparam[opt] integer port the address's second integer: the destination port number for
*   `AF_INET`, the interface index for `AF_PACKET`, the multicast groups for `AF_NETLINK`.
* @treturn integer|boolean number of bytes sent, short of the message's length on a stream socket
*   whose wait ended with part of it queued; `false` when a send timeout ended the wait with
*   nothing queued.
* @raise Error if the send operation fails or if address parameters are incorrect for the socket type,
*   or on a netlink socket under RTNL, as from a netdevice callback; `EAGAIN` when the kernel finds
*   no free port to bind an unbound `AF_INET` or `AF_INET6` socket to before it sends.
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

	bool unbound = luasocket_isunbound(socket); /* the send binds it, or fails with EAGAIN */
	ret = kernel_sendmsg(socket, &msg, &vec, 1, len);
	if (ret == -EAGAIN && !(unbound && luasocket_isunbound(socket)))
		lua_pushboolean(L, false);
	else if (ret < 0)
		lunatik_throw(L, ret);
	else
		lua_pushinteger(L, ret);
	return 1;
}

static int luasocket_receivemsg(lua_State *L, struct msghdr *msg)
{
	struct socket *socket = luasocket_check(L, 1);
	size_t len = (size_t)lunatik_checkinteger(L, 2, 0, INT_MAX);
	int flags = luaL_opt(L, luasocket_checkint, 3, 0);
	luaL_Buffer B;
	struct kvec vec;
	int ret;

	luasocket_checkrtnl(L, socket);

	vec.iov_base = (void *)luaL_buffinitsize(L, &B, len);
	vec.iov_len = len;

	if ((ret = kernel_recvmsg(socket, msg, &vec, 1, len, flags)) >= 0)
		luaL_pushresultsize(&B, ret);
	return ret;
}

/***
* Receives a message from the socket.
* The call blocks until a message arrives, with no timeout of its own, unless `flags` carries
* `linux.socket.msg.DONTWAIT` or `setsockopt` set a receive timeout
* (`linux.socket.so.RCVTIMEO_NEW`); either makes a wait with nothing to read answer `nil`.
* A `lunatik stop` of the spawned thread that waits ends its wait, which raises `ERESTARTSYS`, or
* `EINTR` under a receive timeout; a thread nothing stops, as a worker a body starts with
* `thread.run()`, bounds every wait.
*
* @function receive
* @tparam integer length maximum number of bytes to receive, from 0 to `INT_MAX`.
* @tparam[opt=0] integer flags Optional message flags (e.g., `linux.socket.msg.PEEK`).
*   See the `linux.socket.msg` table for available flags. These can be OR'd together.
* @treturn string received message (as a string of bytes); on a stream socket, the empty string is
*   the end of file, once the peer has shut down its side; `nil` and `"EAGAIN"` when the wait ended
*   with nothing to read.
* @raise Error if the receive operation fails, or on a netlink socket under RTNL, as from a netdevice
*   callback.
* @usage
*   -- For a connected TCP socket:
*   local data = tcp_conn_sock:receive(1024)
*   print("Received:", data)
* @see receivefrom
* @see linux.socket.msg
*/
static int luasocket_receive(lua_State *L)
{
	struct msghdr msg;

	luasocket_setmsg(msg);
	int ret = luasocket_receivemsg(L, &msg);
	return ret < 0 ? luasocket_pushfail(L, ret, ret == -EAGAIN) : 1;
}

/***
* Receives a message from the socket, and the address of its sender.
* It waits as `receive` does. A connectionless socket (`SOCK_DGRAM`) names the sender of each
* message; TCP names none, and neither does an `AF_UNIX` peer that never bound, and nothing follows
* the message then.
*
* @function receivefrom
* @tparam integer length maximum number of bytes to receive, as `receive` takes it.
* @tparam[opt=0] integer flags message flags, as `receive` takes them.
* @treturn string received message, as `receive` returns it; `nil` and `"EAGAIN"`, in place of the
*   message and the address, when the wait ended with nothing to read.
* @treturn[opt] integer|string addr the sender's address (two values for `AF_INET` and `AF_NETLINK`,
*   five for `AF_PACKET`).
*   - For `AF_INET`: An integer representing the IPv4 address (can be converted with `net.ntoa()`).
*   - For `AF_PACKET`: The frame's ethertype, in host byte order.
*   - For `AF_UNIX`: The sender's name, carrying its leading NUL when the name is an abstract one.
*   - For `AF_NETLINK`: The sender's port id.
*   - For other families: A packed string of the sender's address past the family, of the length the
*     protocol reports.
* @treturn[opt] integer port the sender's port number for `AF_INET`, the index of the interface the
*   frame arrived on for `AF_PACKET`, and its multicast groups for `AF_NETLINK`.
* @treturn[opt] integer pkttype For `AF_PACKET`, the frame's packet type.
* @treturn[opt] integer hatype For `AF_PACKET`, the interface's hardware type.
* @treturn[opt] string hwaddr For `AF_PACKET`, the sender's hardware address.
* @raise Error if the receive operation fails, or on a netlink socket under RTNL, as from a netdevice
*   callback.
* @usage
*   -- For a UDP socket, getting sender info:
*   local data, sender_ip_int, sender_port = udp_sock:receivefrom(1500)
*   print("Received from " .. net.ntoa(sender_ip_int) .. ":" .. sender_port .. ": " .. data)
* @see receive
* @see net.ntoa
*/
static int luasocket_receivefrom(lua_State *L)
{
	struct msghdr msg;
	struct sockaddr_storage addr;

	luasocket_setmsg(msg);
	msg.msg_name = &addr;
	int ret = luasocket_receivemsg(L, &msg);
	if (ret < 0)
		return luasocket_pushfail(L, ret, ret == -EAGAIN);

	/* msg_namelen is an output: zero means the protocol named no address */
	return luasocket_pushaddr(L, &addr, msg.msg_namelen) + 1;
}

/***
* Binds the socket to a local address.
* This is typically used on the server side before calling `listen()` or on
* connectionless sockets to specify a local port/interface for receiving.
*
* @function bind
* @tparam integer|string addr local address to bind to. Interpretation depends on the family the
*   socket was created with:
*
*   - `AF_INET` (IPv4): An integer representing the IPv4 address (e.g., from `net.aton()`).
*     Use `0` (or `net.aton("0.0.0.0")`) to bind to all available interfaces.
*     The `port` argument is also required.
*   - `AF_PACKET`: An integer representing the ethernet protocol in host byte order
*     (e.g., `0x0003` for `ETH_P_ALL`, `0x88CC` for `ETH_P_LLDP`)
*     The `port` argument is also required.
*   - `AF_NETLINK`: The port id, 0 to let the kernel pick one; `port` carries the multicast groups.
*   - `AF_UNIX`: A filesystem path, or, when its first byte is NUL (e.g. `"\0name"`), a name in the
*     abstract namespace, which is registered as the exact bytes given, so a peer of any kind reaches
*     it by the same string. The empty string asks the kernel to pick a name (autobind).
*   - Other families: A packed string directly representing parts of the family-specific address structure.
*
* @tparam[opt] integer port local port or interface index.
*   - `AF_INET`: TCP/UDP port number.
*   - `AF_PACKET`: Network interface index (e.g., from `linux.ifindex("eth0")`).
*   - `AF_NETLINK`: Multicast groups to join.
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
	int backlog = luaL_opt(L, luasocket_checkint, 2, SOMAXCONN);

	lunatik_try(L, kernel_listen, socket, backlog);
	return 0;
}

/***
* Initiates a connection on a socket.
* This is typically used by client sockets to establish a connection to a server.
* For datagram sockets, this sets the default destination address for `send` and
* the only address from which datagrams are received.
* A TCP connect waits for the connection, with no timeout of its own, unless `flags` carries
* `O_NONBLOCK` or `setsockopt` set a send timeout; either makes a wait that ends with the connection
* still in progress answer `nil`, whether this connect or an earlier one started it, and `send` says
* how a stop ends the wait. An `AF_UNIX` connect waits the same way for room in the backlog of the
* listener it reaches, and a wait that ends with none answers `false`.
*
* @function connect
* @tparam integer|string addr destination address to connect to.
*   Interpretation depends on the family the socket was created with:
*
*   - `AF_INET` (IPv4): An integer representing the IPv4 address (e.g., from `net.aton()`).
*     The `port` argument is also required.
*   - `AF_PACKET` and `AF_NETLINK`: The first of the two integers the `socket` type describes.
*   - Other families: The address as the `socket` type describes it.
* @tparam[opt] integer port the address's second integer, for `AF_INET`, `AF_PACKET` and
*   `AF_NETLINK`; for any other family, `flags` takes this place.
* @tparam[opt=0] integer flags file status flags: `O_NONBLOCK` makes a connect that cannot
*   complete at once not wait for it. `linux.socket.sock.NONBLOCK` carries
*   `O_NONBLOCK` on every architecture but alpha and parisc.
* @treturn boolean `true` once connected; `nil` and `"EINPROGRESS"` when the wait ended with the
*   connection it started still in progress, or `"EALREADY"` with one an earlier connect started;
*   `false` when it ended with no room in an `AF_UNIX` listener's backlog.
* @raise Error if the connect operation fails (e.g., connection refused, host unreachable).
* @usage
*   tcp_client_sock:connect(net.aton("192.168.1.100"), 80)
*/
static int luasocket_connect(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	struct sockaddr_storage addr;
	size_t size = luasocket_checkaddr(L, socket, &addr, 2);
	int flags = luaL_opt(L, luasocket_checkint, luasocket_ispair(luasocket_family(socket)) ? 4 : 3, 0);
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 19, 0))
	int ret = kernel_connect(socket, (struct sockaddr_unsized *)&addr, size, flags);
#else
	int ret = kernel_connect(socket, (struct sockaddr *)&addr, size, flags);
#endif

	if (ret == -EAGAIN && LUASOCKET_ISUNIX(luasocket_family(socket))) /* inet's is a failed autobind */
		lua_pushboolean(L, false);
	else if (ret < 0)
		return luasocket_pushfail(L, ret, ret == -EINPROGRESS || ret == -EALREADY);
	else
		lua_pushboolean(L, true);
	return 1;
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
* - For `AF_PACKET`: The ethertype the socket was created or bound with, in host byte order.
* - For `AF_UNIX`: The bound name, carrying its leading NUL when the name is an abstract one, and the
*   empty string when the socket is unbound.
* - For `AF_NETLINK`: The port id.
* - For other families: A packed string of the address bytes past the family, of the length the kernel
*   reports.
* @treturn[opt] integer port The local port number for `AF_INET`, the interface index for `AF_PACKET`,
*   0 when unbound, and the multicast groups for `AF_NETLINK`.
* @treturn[opt] integer pkttype For `AF_PACKET`, 0.
* @treturn[opt] integer hatype For `AF_PACKET`, the interface's hardware type, 0 when unbound.
* @treturn[opt] string hwaddr For `AF_PACKET`, the interface's hardware address, empty when unbound.
* @raise Error if the operation fails.
* @usage
*   -- an AF_INET socket
*   local local_ip_int, local_port = my_socket:getsockname()
*   print("Bound to " .. net.ntoa(local_ip_int) .. ":" .. local_port)
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
* - For `AF_NETLINK`: The peer's port id.
* - For other families: A packed string of the address bytes past the family, of the length the kernel
*   reports.
* @treturn[opt] integer port The peer's port number for `AF_INET`, and its multicast groups for
*   `AF_NETLINK`.
* @raise Error if the operation fails (e.g., socket not connected); `EOPNOTSUPP` on an `AF_PACKET`
*   socket, which names no peer.
* @usage
*   -- a connected AF_INET socket
*   local peer_ip_int, peer_port = connected_socket:getpeername()
*   print("Connected to " .. net.ntoa(peer_ip_int) .. ":" .. peer_port)
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
*   payload, from `INT_MIN` to `UINT_MAX`, since an unsigned option such as `SO_MARK` reads
*   those 32 bits as a `u32`, or a string carrying the option's packed binary payload.
* @raise Error if the operation fails, or at a level other than `SOL_SOCKET` under RTNL, as from a
*   netdevice callback; `unsupported option level` on a kernel before 6.7, at a level the socket's
*   protocol has no `setsockopt` for.
* @usage
*   -- bound blocking receives to 500 ms (a `struct __kernel_sock_timeval`)
*   sock:setsockopt(sol.SOCKET, so.RCVTIMEO_NEW, timeval:pack(0, 500000))
*/
static int luasocket_setsockopt(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	int level = luasocket_checkint(L, 2);
	int optname = luasocket_checkint(L, 3);
	int value;
	size_t len;
	const char *optval;

	if (level != SOL_SOCKET) /* a protocol's options can take RTNL, for a multicast membership among others */
		lunatik_checkrtnl(L);

	if (lua_type(L, 4) == LUA_TSTRING)
		optval = lua_tolstring(L, 4, &len);
	else {
		value = (int)lunatik_checkinteger(L, 4, INT_MIN, UINT_MAX); /* unsigned options read a u32 */
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
	{"receivefrom", luasocket_receivefrom},
	{"bind", luasocket_bind},
	{"listen", luasocket_listen},
	{"accept", luasocket_accept},
	{"connect", luasocket_connect},
	{"setsockopt", luasocket_setsockopt},
	{"getsockname", luasocket_getsockname},
	{"getpeername", luasocket_getpeername},
	{NULL, NULL}
};

static const lunatik_class_t luasocket_class = {
	.name = "socket",
	.methods = luasocket_mt,
	.release = luasocket_release,
	.opt = LUNATIK_OPT_MONITOR | LUNATIK_OPT_EXTERNAL,
	.owner = THIS_MODULE,
};

#define luasocket_new(L)		(lunatik_newobject((L), &luasocket_class, 0, LUNATIK_OPT_NONE))
#define luasocket_psocket(object)	((struct socket **)&object->private)

/* a kernel socket holds no reference on its namespace, and a TCP one outlives its release with timers armed */
#if defined(LUNATIK_SK_NET_REFCNT_UPGRADE)
#define luasocket_upgrade(sk)		sk_net_refcnt_upgrade(sk)
#define luasocket_getnetbypid(pid)	lualinux_getnetbypid(pid)
#elif defined(LUNATIK_NET_PASSIVE_DEC)
/* the upgrade drops a passive reference through net_passive_dec, which is not exported: init_net only */
#define luasocket_upgrade(sk)
#define luasocket_getnetbypid(pid)	ERR_PTR(-EOPNOTSUPP)
#else
#define luasocket_getnetbypid(pid)	lualinux_getnetbypid(pid)
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
* The call blocks until a connection arrives, with no timeout of its own, unless `flags` carries
* `O_NONBLOCK` or `setsockopt` set a receive timeout; either makes a wait with no connection to
* accept answer `nil`, and `receive` says how a stop ends the wait.
*
* @function accept
* @tparam[opt=0] integer flags file status flags: `O_NONBLOCK` makes the call answer at once when no
*   connection is pending instead of waiting for one. `linux.socket.sock.NONBLOCK` carries
*   `O_NONBLOCK` on every architecture but alpha and parisc.
* @treturn socket A new socket object representing the accepted connection; `nil` and `"EAGAIN"`
*   when the wait ended with no connection to accept.
* @raise Error if the accept operation fails.
*/
static int luasocket_accept(lua_State *L)
{
	struct socket *socket = luasocket_check(L, 1);
	int flags = luaL_opt(L, luasocket_checkint, 2, 0);
	lunatik_object_t *object = luasocket_new(L);
	int ret = kernel_accept(socket, luasocket_psocket(object), flags);

	if (ret < 0)
		return luasocket_pushfail(L, ret, ret == -EAGAIN);
	return 1; /* object */
}

/***
* Creates a new socket object.
* This function is the primary way to create a socket.
*
* @function new
* @tparam integer family address family (e.g., `linux.socket.af.INET`).
* @tparam integer type socket type (e.g., `linux.socket.sock.STREAM`). `linux.socket.sock.PACKET` is
*   refused; `SOCK_RAW` and `SOCK_DGRAM` replace it on `AF_PACKET`.
* @tparam integer protocol protocol (e.g., `linux.socket.ipproto.TCP`).
*   For `AF_PACKET` sockets, `protocol` is an ethertype in host byte order, as `bind` takes it
*   (e.g., `linux.eth.ALL` for every frame).
* @tparam[opt] integer pid a task whose network namespace the socket is created in, instead of the
*   initial one. The pid is read in the initial pid namespace: the number `task:pid()` returns,
*   whichever task makes the call. The socket holds its network namespace until the kernel frees the
*   socket, which for a TCP connection still shutting down comes after its close, so the namespace
*   outlives the task. The rest of Lunatik (`linux.ifindex`, `netfilter`) keeps to the initial network
*   namespace.
* @treturn socket A new socket object. A socket a netdevice callback may collect is closed by the
*   script first, not dropped: its release cannot refuse where the collector drops it.
* @raise Error if socket creation fails, "unsupported socket type" for `linux.socket.sock.PACKET`,
*   "out of bounds" for an argument past an `int`, an `AF_PACKET` protocol past 16 bits or a pid
*   outside 1 to `PID_MAX_LIMIT`,
*   `ESRCH` if no task has that pid, `EOPNOTSUPP` on a kernel whose sockets cannot hold a namespace
*   of their own, or
*   `'socket': process-context class in interrupt-context runtime` in a softirq or hardirq runtime.
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
	int family = luasocket_checkint(L, 1);
	int type = luasocket_checkint(L, 2);
	luaL_argcheck(L, type != SOCK_PACKET, 2, "unsupported socket type");
	int proto = family == AF_PACKET ? (__force u16)luasocket_checkethertype(L, 3) : luasocket_checkint(L, 3);
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
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

