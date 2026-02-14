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
* @tparam string message The string message to send.
* @tparam[opt] integer|string addr The destination address.
*
* - For `AF_INET` (IPv4) sockets: An integer representing the IPv4 address (e.g., from `net.aton()`).
* - For other address families (e.g., `AF_PACKET`): A packed string representing the destination address
*   (e.g., MAC address for `AF_PACKET`). The exact format depends on the family.
* @tparam[opt] integer port The destination port number (required if `addr` is an IPv4 address for `AF_INET`).
* @treturn integer The number of bytes sent.
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
* @tparam integer length The maximum number of bytes to receive.
* @tparam[opt=0] integer flags Optional message flags (e.g., `socket.msg.PEEK`).
*   See the `socket.msg` table for available flags. These can be OR'd together.
* @tparam[opt=false] boolean from If `true`, the function also returns the sender's address
*   and port (for `AF_INET`). This is typically used with connectionless sockets (`SOCK_DGRAM`).
* @treturn string The received message (as a string of bytes).
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
* @see socket.msg
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
* @tparam integer|string addr The local address to bind to. The interpretation depends on `socket.sk.sk_family`:
*
*   - `AF_INET` (IPv4): An integer representing the IPv4 address (e.g., from `net.aton()`).
*     Use `0` (or `net.aton("0.0.0.0")`) to bind to all available interfaces.
*     The `port` argument is also required.
*   - `AF_PACKET`: An integer representing the ethernet protocol in host byte order
*     (e.g., `0x0003` for `ETH_P_ALL`, `0x88CC` for `ETH_P_LLDP`)
*     The `port` argument is also required.
*   - Other families: A packed string directly representing parts of the family-specific address structure.
*
* @tparam[opt] integer port The local port or interface index.
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
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0))
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
* @tparam[opt] integer backlog The maximum length of the queue for pending connections.
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
* @tparam integer|string addr The destination address to connect to.
*   Interpretation depends on `socket.sk.sk_family`:
*
*   - `AF_INET` (IPv4): An integer representing the IPv4 address (e.g., from `net.aton()`).
*     The `port` argument is also required.
*   - Other families: A packed string representing the family-specific destination address.
* @tparam[opt] integer port The destination port number (required and used only if the family is `AF_INET`).
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

#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 18, 0))
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
* @treturn integer|string addr The local address.
*
* - For `AF_INET`: An integer representing the IPv4 address (can be converted with `net.ntoa()`).
* - For other families: A packed string representing the local address.
* @treturn[opt] integer port If the family is `AF_INET`, the local port number.
* @raise Error if the operation fails.
* @usage
*   local local_ip_int, local_port = my_socket:getsockname()
*   if my_socket.sk.sk_family == socket.af.INET then print("Bound to " .. net.ntoa(local_ip_int) .. ":" .. local_port) end
*/
LUASOCKET_NEWGETTER(sockname);

/***
* Gets the address of the peer to which the socket is connected.
* This is typically used with connection-oriented sockets after a connection
* has been established, or with connectionless sockets after `connect()` has
* been called to set a default peer.
*
* @function getpeername
* @treturn integer|string addr The peer's address.
*
* - For `AF_INET`: An integer representing the IPv4 address (can be converted with `net.ntoa()`).
* - For other families: A packed string representing the peer's address.
* @treturn[opt] integer port If the family is `AF_INET`, the peer's port number.
* @raise Error if the operation fails (e.g., socket not connected).
* @usage
*   local peer_ip_int, peer_port = connected_socket:getpeername()
*   if connected_socket.sk.sk_family == socket.af.INET then print("Connected to " .. net.ntoa(peer_ip_int) .. ":" .. peer_port) end
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

/***
* Table of address family constants.
* These constants are used in `socket.new()` to specify the
* communication domain of the socket.
* (Constants from `<linux/socket.h>`)
* @table af
*
*   @tfield integer UNSPEC Unspecified.
*   @tfield integer UNIX Unix domain sockets.
*   @tfield integer LOCAL POSIX name for AF_UNIX.
*   @tfield integer INET Internet IP Protocol (IPv4).
*   @tfield integer AX25 Amateur Radio AX.25.
*   @tfield integer IPX Novell IPX.
*   @tfield integer APPLETALK AppleTalk DDP.
*   @tfield integer NETROM Amateur Radio NET/ROM.
*   @tfield integer BRIDGE Multiprotocol bridge.
*   @tfield integer ATMPVC ATM PVCs.
*   @tfield integer X25 Reserved for X.25 project.
*   @tfield integer INET6 IP version 6.
*   @tfield integer ROSE Amateur Radio X.25 PLP.
*   @tfield integer DECnet Reserved for DECnet project.
*   @tfield integer NETBEUI Reserved for 802.2LLC project.
*   @tfield integer SECURITY Security callback pseudo AF.
*   @tfield integer KEY PF_KEY key management API.
*   @tfield integer NETLINK Netlink.
*   @tfield integer ROUTE Alias to emulate 4.4BSD.
*   @tfield integer PACKET Packet family.
*   @tfield integer ASH Ash.
*   @tfield integer ECONET Acorn Econet.
*   @tfield integer ATMSVC ATM SVCs.
*   @tfield integer RDS RDS sockets.
*   @tfield integer SNA Linux SNA Project.
*   @tfield integer IRDA IRDA sockets.
*   @tfield integer PPPOX PPPoX sockets.
*   @tfield integer WANPIPE Wanpipe API Sockets.
*   @tfield integer LLC Linux LLC.
*   @tfield integer IB Native InfiniBand address.
*   @tfield integer MPLS MPLS.
*   @tfield integer CAN Controller Area Network.
*   @tfield integer TIPC TIPC sockets.
*   @tfield integer BLUETOOTH Bluetooth sockets.
*   @tfield integer IUCV IUCV sockets.
*   @tfield integer RXRPC RxRPC sockets.
*   @tfield integer ISDN mISDN sockets.
*   @tfield integer PHONET Phonet sockets.
*   @tfield integer IEEE802154 IEEE802154 sockets.
*   @tfield integer CAIF CAIF sockets.
*   @tfield integer ALG Algorithm sockets.
*   @tfield integer NFC NFC sockets.
*   @tfield integer VSOCK vSockets.
*   @tfield integer KCM Kernel Connection Multiplexor.
*   @tfield integer QIPCRTR Qualcomm IPC Router.
*   @tfield integer SMC SMCP sockets (PF_SMC reuses AF_INET).
*   @tfield integer XDP XDP sockets.
*   @tfield integer MCTP Management component transport protocol (Kernel 5.15+).
*   @tfield integer MAX Maximum value for AF constants.
*
* @within socket
*/
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
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 15, 0)
	{"MCTP", AF_MCTP},
#endif
	{"MAX", AF_MAX},
	{NULL, 0}
};

/***
* Table of message flags.
* These flags can be used with `sock:receive()` and `sock:send()`
* to modify their behavior.
* (Constants from `<linux/socket.h>`)
* @table msg
*
*   @tfield integer OOB Process out-of-band data.
*   @tfield integer PEEK Peek at incoming message without removing it from the queue.
*   @tfield integer DONTROUTE Don't use a gateway to send out the packet.
*   @tfield integer TRYHARD Synonym for DONTROUTE for DECnet.
*   @tfield integer CTRUNC Control data lost before delivery.
*   @tfield integer PROBE Do not send data, only probe path (e.g., for MTU discovery).
*   @tfield integer TRUNC Normal data lost before delivery.
*   @tfield integer DONTWAIT Enables non-blocking operation.
*   @tfield integer EOR Terminates a record (if supported by the protocol).
*   @tfield integer WAITALL Wait for full request or error.
*   @tfield integer FIN FIN segment.
*   @tfield integer SYN SYN segment.
*   @tfield integer CONFIRM Confirm path validity (e.g., ARP entry).
*   @tfield integer RST RST segment.
*   @tfield integer ERRQUEUE Fetch message from error queue.
*   @tfield integer NOSIGNAL Do not generate SIGPIPE.
*   @tfield integer MORE Sender will send more data.
*   @tfield integer WAITFORONE For `recvmmsg()`: block until at least one packet is available.
*   @tfield integer SENDPAGE_NOPOLICY Internal: `sendpage()` should not apply policy.
*   @tfield integer BATCH For `sendmmsg()`: more messages are coming.
*   @tfield integer EOF End of file.
*   @tfield integer NO_SHARED_FRAGS Internal: `sendpage()` page fragments are not shared.
*   @tfield integer SENDPAGE_DECRYPTED Internal: `sendpage()` page may carry plain text and require encryption.
*   @tfield integer ZEROCOPY Use user data in kernel path for zero-copy transmit.
*   @tfield integer FASTOPEN Send data in TCP SYN (TCP Fast Open).
*   @tfield integer CMSG_CLOEXEC Set close-on-exec for file descriptor received via SCM_RIGHTS.
*
* @within socket
*/
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
#if LINUX_VERSION_CODE < KERNEL_VERSION(6, 4, 0)
	{"SENDPAGE_NOTLAST", MSG_SENDPAGE_NOTLAST},
#endif
	{"BATCH", MSG_BATCH},
	{"EOF", MSG_EOF},
	{"NO_SHARED_FRAGS", MSG_NO_SHARED_FRAGS},
	{"SENDPAGE_DECRYPTED", MSG_SENDPAGE_DECRYPTED},
	{"ZEROCOPY", MSG_ZEROCOPY},
	{"FASTOPEN", MSG_FASTOPEN},
	{"CMSG_CLOEXEC", MSG_CMSG_CLOEXEC},
	{NULL, 0}
};

/***
* Table of socket type and flag constants.
* Socket types are used in `socket.new()`. Socket flags can be used in
* `socket.new()` (by ORing with type), `sock:accept()`, and `sock:connect()`.
* (Constants from `<linux/net.h>`)
* @table sock
*   @tfield integer STREAM Stream socket (e.g., TCP).
*   @tfield integer DGRAM Datagram socket (e.g., UDP).
*   @tfield integer RAW Raw socket.
*   @tfield integer RDM Reliably-delivered message socket.
*   @tfield integer SEQPACKET Sequential packet socket.
*   @tfield integer DCCP Datagram Congestion Control Protocol socket.
*   @tfield integer PACKET Linux specific packet socket (deprecated in favor of AF_PACKET).
*   @tfield integer CLOEXEC Atomically set the close-on-exec flag for the new socket.
*   @tfield integer NONBLOCK Atomically set the O_NONBLOCK flag for the new socket.
* @within socket
*/
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

/***
* Table of IP protocol constants.
* These are used in `socket.new()` to specify the protocol for `AF_INET` or `AF_INET6` sockets.
* (Constants from `<uapi/linux/in.h>`)
* @table ipproto
*   @tfield integer IP Dummy protocol for TCP. (Typically 0)
*   @tfield integer ICMP Internet Control Message Protocol.
*   @tfield integer IGMP Internet Group Management Protocol.
*   @tfield integer IPIP IPIP tunnels.
*   @tfield integer TCP Transmission Control Protocol.
*   @tfield integer EGP Exterior Gateway Protocol.
*   @tfield integer PUP PUP protocol.
*   @tfield integer UDP User Datagram Protocol.
*   @tfield integer IDP XNS IDP protocol.
*   @tfield integer TP SO Transport Protocol Class 4.
*   @tfield integer DCCP Datagram Congestion Control Protocol.
*   @tfield integer IPV6 IPv6-in-IPv4 tunnelling.
*   @tfield integer RSVP RSVP Protocol.
*   @tfield integer GRE Cisco GRE tunnels.
*   @tfield integer ESP Encapsulation Security Payload protocol.
*   @tfield integer AH Authentication Header protocol.
*   @tfield integer MTP Multicast Transport Protocol.
*   @tfield integer BEETPH IP option pseudo header for BEET.
*   @tfield integer ENCAP Encapsulation Header.
*   @tfield integer PIM Protocol Independent Multicast.
*   @tfield integer COMP Compression Header Protocol.
*   @tfield integer L2TP Layer Two Tunneling Protocol.
*   @tfield integer SCTP Stream Control Transport Protocol.
*   @tfield integer UDPLITE UDP-Lite (RFC 3828).
*   @tfield integer MPLS MPLS in IP (RFC 4023).
*   @tfield integer ETHERNET Ethernet-within-IPv6 Encapsulation (Kernel 5.6+).
*   @tfield integer RAW Raw IP packets.
*   @tfield integer MPTCP Multipath TCP connection (Kernel 5.6+).
* @within socket
*/
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
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
	{"ETHERNET", IPPROTO_ETHERNET},
#endif
	{"RAW", IPPROTO_RAW},
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 6, 0)
	{"MPTCP", IPPROTO_MPTCP},
#endif
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
	.shared = true,
	.pointer = true,
};

#define luasocket_newsocket(L)		(lunatik_newobject((L), &luasocket_class, 0))
#define luasocket_psocket(object)	((struct socket **)&object->private)

/***
* Accepts a connection on a listening socket.
* This function is used with connection-oriented sockets (e.g., `SOCK_STREAM`)
* that have been put into the listening state by `sock:listen()`.
*
* @function accept
* @tparam socket self The listening socket object.
* @tparam[opt=0] integer flags Optional flags to apply to the newly accepted socket
*   (e.g., `socket.sock.NONBLOCK`, `socket.sock.CLOEXEC`).
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
* @tparam integer family The address family for the socket (e.g., `socket.af.INET`).
* @tparam integer type The type of the socket (e.g., `socket.sock.STREAM`).
* @tparam integer protocol The protocol to be used (e.g., `socket.ipproto.TCP`).
*   For `AF_PACKET` sockets, `protocol` is typically an `ETH_P_*` value in network byte order
*   (e.g., `linux.hton16(0x0003)` for `ETH_P_ALL`).
* @treturn socket A new socket object.
* @raise Error if socket creation fails.
* @usage
*   -- TCP/IPv4 socket
*   local tcp_sock = socket.new(socket.af.INET, socket.sock.STREAM, socket.ipproto.TCP)
* @see socket.af
* @see socket.sock
* @see socket.ipproto
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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

