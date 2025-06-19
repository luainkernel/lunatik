/*
 * sys/socket.h
 */

#ifndef _SYS_SOCKET_H
#define _SYS_SOCKET_H

#include <sys/types.h>
#include <klibc/extern.h>
#include <klibc/compiler.h>
#include <klibc/sysconfig.h>
#include <linux/socket.h>
#include <linux/uio.h>
#include <asm/socket.h>
#if _KLIBC_HAS_ARCHSOCKET_H
#include <klibc/archsocket.h>
#endif

/* Great job, guys!  These are *architecture-specific* ABI constants,
   that are hidden under #ifdef __KERNEL__... what a brilliant idea!
   These are the "common" definitions; if not appropriate, override
   them in <klibc/archsocket.h>. */

#ifndef SOCK_STREAM
# define SOCK_STREAM    1
# define SOCK_DGRAM     2
# define SOCK_RAW       3
# define SOCK_RDM       4
# define SOCK_SEQPACKET 5
# define SOCK_PACKET    10
# define SOCK_CLOEXEC   02000000
# define SOCK_NONBLOCK  04000
#endif

/* The maximum backlock queue length. */
#define SOMAXCONN	128

#ifndef AF_INET
#define AF_UNSPEC	0
#define AF_UNIX		1	/* Unix domain sockets 		*/
#define AF_LOCAL	1	/* POSIX name for AF_UNIX	*/
#define AF_INET		2	/* Internet IP Protocol 	*/
#define AF_AX25		3	/* Amateur Radio AX.25 		*/
#define AF_IPX		4	/* Novell IPX 			*/
#define AF_APPLETALK	5	/* AppleTalk DDP 		*/
#define AF_NETROM	6	/* Amateur Radio NET/ROM 	*/
#define AF_BRIDGE	7	/* Multiprotocol bridge 	*/
#define AF_ATMPVC	8	/* ATM PVCs			*/
#define AF_X25		9	/* Reserved for X.25 project 	*/
#define AF_INET6	10	/* IP version 6			*/
#define AF_ROSE		11	/* Amateur Radio X.25 PLP	*/
#define AF_DECnet	12	/* Reserved for DECnet project	*/
#define AF_NETBEUI	13	/* Reserved for 802.2LLC project*/
#define AF_SECURITY	14	/* Security callback pseudo AF */
#define AF_KEY		15      /* PF_KEY key management API */
#define AF_NETLINK	16
#define AF_ROUTE	AF_NETLINK /* Alias to emulate 4.4BSD */
#define AF_PACKET	17	/* Packet family		*/
#define AF_ASH		18	/* Ash				*/
#define AF_ECONET	19	/* Acorn Econet			*/
#define AF_ATMSVC	20	/* ATM SVCs			*/
#define AF_RDS		21	/* RDS sockets 			*/
#define AF_SNA		22	/* Linux SNA Project (nutters!) */
#define AF_IRDA		23	/* IRDA sockets			*/
#define AF_PPPOX	24	/* PPPoX sockets		*/
#define AF_WANPIPE	25	/* Wanpipe API Sockets */
#define AF_LLC		26	/* Linux LLC			*/
#define AF_CAN		29	/* Controller Area Network      */
#define AF_TIPC		30	/* TIPC sockets			*/
#define AF_BLUETOOTH	31	/* Bluetooth sockets 		*/
#define AF_IUCV		32	/* IUCV sockets			*/
#define AF_RXRPC	33	/* RxRPC sockets 		*/
#define AF_ISDN		34	/* mISDN sockets 		*/
#define AF_PHONET	35	/* Phonet sockets		*/
#define AF_IEEE802154	36	/* IEEE802154 sockets		*/
#define AF_MAX		37	/* For now.. */
#endif // !AF_INET

#ifndef PF_UNSPEC
#define PF_UNSPEC	AF_UNSPEC
#define PF_UNIX		AF_UNIX
#define PF_LOCAL	AF_LOCAL
#define PF_INET		AF_INET
#define PF_AX25		AF_AX25
#define PF_IPX		AF_IPX
#define PF_APPLETALK	AF_APPLETALK
#define	PF_NETROM	AF_NETROM
#define PF_BRIDGE	AF_BRIDGE
#define PF_ATMPVC	AF_ATMPVC
#define PF_X25		AF_X25
#define PF_INET6	AF_INET6
#define PF_ROSE		AF_ROSE
#define PF_DECnet	AF_DECnet
#define PF_NETBEUI	AF_NETBEUI
#define PF_SECURITY	AF_SECURITY
#define PF_KEY		AF_KEY
#define PF_NETLINK	AF_NETLINK
#define PF_ROUTE	AF_ROUTE
#define PF_PACKET	AF_PACKET
#define PF_ASH		AF_ASH
#define PF_ECONET	AF_ECONET
#define PF_ATMSVC	AF_ATMSVC
#define PF_RDS		AF_RDS
#define PF_SNA		AF_SNA
#define PF_IRDA		AF_IRDA
#define PF_PPPOX	AF_PPPOX
#define PF_WANPIPE	AF_WANPIPE
#define PF_LLC		AF_LLC
#define PF_CAN		AF_CAN
#define PF_TIPC		AF_TIPC
#define PF_BLUETOOTH	AF_BLUETOOTH
#define PF_IUCV		AF_IUCV
#define PF_RXRPC	AF_RXRPC
#define PF_ISDN		AF_ISDN
#define PF_PHONET	AF_PHONET
#define PF_IEEE802154	AF_IEEE802154
#define PF_MAX		AF_MAX
#endif // !PF_UNSPEC

#ifndef MSG_OOB
#define MSG_OOB		1
#define MSG_PEEK	2
#define MSG_DONTROUTE	4
#define MSG_TRYHARD     4       /* Synonym for MSG_DONTROUTE for DECnet */
#define MSG_CTRUNC	8
#define MSG_PROBE	0x10	/* Do not send. Only probe path f.e. for MTU */
#define MSG_TRUNC	0x20
#define MSG_DONTWAIT	0x40	/* Nonblocking io		 */
#define MSG_EOR         0x80	/* End of record */
#define MSG_WAITALL	0x100	/* Wait for a full request */
#define MSG_FIN         0x200
#define MSG_SYN		0x400
#define MSG_CONFIRM	0x800	/* Confirm path validity */
#define MSG_RST		0x1000
#define MSG_ERRQUEUE	0x2000	/* Fetch message from error queue */
#define MSG_NOSIGNAL	0x4000	/* Do not generate SIGPIPE */
#define MSG_MORE	0x8000	/* Sender will send more */

#define MSG_EOF         MSG_FIN

#define MSG_CMSG_CLOEXEC 0x40000000	/* Set close_on_exit for file
					   descriptor received through
					   SCM_RIGHTS */
#if defined(CONFIG_COMPAT)
#define MSG_CMSG_COMPAT	0x80000000	/* This message needs 32 bit fixups */
#else
#define MSG_CMSG_COMPAT	0		/* We never have 32 bit fixups */
#endif
#endif // !MSG_OOB

/* These types is hidden under __KERNEL__ in kernel sources */
typedef unsigned short sa_family_t;
struct sockaddr {
	sa_family_t     sa_family;      /* address family, AF_xxx       */
	char            sa_data[14];    /* 14 bytes of protocol address */
};
typedef int socklen_t;
struct msghdr {
	void *msg_name;
	int msg_namelen;
	struct iovec *msg_iov;
	size_t msg_iovlen;
	void *msg_control;
	size_t msg_controllen;
	unsigned msg_flags;
};

/* Ancillary data structures and cmsg macros are also hidden under __KERNEL__ */
#ifndef CMSG_FIRSTHDR
/*
 *	POSIX 1003.1g - ancillary data object information
 *	Ancillary data consits of a sequence of pairs of
 *	(cmsghdr, cmsg_data[])
 */

struct cmsghdr {
	__kernel_size_t	cmsg_len;	/* data byte count, including hdr */
        int		cmsg_level;	/* originating protocol */
        int		cmsg_type;	/* protocol-specific type */
};

/*
 *	Ancilliary data object information MACROS
 *	Table 5-14 of POSIX 1003.1g
 */

#define __CMSG_NXTHDR(ctl, len, cmsg) __cmsg_nxthdr((ctl),(len),(cmsg))
#define CMSG_NXTHDR(mhdr, cmsg) cmsg_nxthdr((mhdr), (cmsg))

#define CMSG_ALIGN(len) ( ((len)+sizeof(long)-1) & ~(sizeof(long)-1) )

#define CMSG_DATA(cmsg)	((void *)((char *)(cmsg) + CMSG_ALIGN(sizeof(struct cmsghdr))))
#define CMSG_SPACE(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + CMSG_ALIGN(len))
#define CMSG_LEN(len) (CMSG_ALIGN(sizeof(struct cmsghdr)) + (len))

#define __CMSG_FIRSTHDR(ctl,len) ((len) >= sizeof(struct cmsghdr) ? \
				  (struct cmsghdr *)(ctl) : \
				  (struct cmsghdr *)NULL)
#define CMSG_FIRSTHDR(msg)	__CMSG_FIRSTHDR((msg)->msg_control, (msg)->msg_controllen)
#define CMSG_OK(mhdr, cmsg) ((cmsg)->cmsg_len >= sizeof(struct cmsghdr) && \
			     (cmsg)->cmsg_len <= (unsigned long) \
			     ((mhdr)->msg_controllen - \
			      ((char *)(cmsg) - (char *)(mhdr)->msg_control)))

/*
 *	Get the next cmsg header
 *
 *	PLEASE, do not touch this function. If you think, that it is
 *	incorrect, grep kernel sources and think about consequences
 *	before trying to improve it.
 *
 *	Now it always returns valid, not truncated ancillary object
 *	HEADER. But caller still MUST check, that cmsg->cmsg_len is
 *	inside range, given by msg->msg_controllen before using
 *	ancillary object DATA.				--ANK (980731)
 */

static inline struct cmsghdr * __cmsg_nxthdr(void *__ctl, __kernel_size_t __size,
					       struct cmsghdr *__cmsg)
{
	struct cmsghdr * __ptr;

	__ptr = (struct cmsghdr*)(((unsigned char *) __cmsg) +  CMSG_ALIGN(__cmsg->cmsg_len));
	if ((unsigned long)((char*)(__ptr+1) - (char *) __ctl) > __size)
		return (struct cmsghdr *)0;

	return __ptr;
}

static inline struct cmsghdr * cmsg_nxthdr (struct msghdr *__msg, struct cmsghdr *__cmsg)
{
	return __cmsg_nxthdr(__msg->msg_control, __msg->msg_controllen, __cmsg);
}

/* "Socket"-level control message types: */

#define	SCM_RIGHTS	0x01		/* rw: access rights (array of int) */
#define SCM_CREDENTIALS 0x02		/* rw: struct ucred		*/
#define SCM_SECURITY	0x03		/* rw: security label		*/

struct ucred {
	__u32	pid;
	__u32	uid;
	__u32	gid;
};
#endif /* CMSG_FIRSTHDR */


__extern int socket(int, int, int);
__extern int bind(int, const struct sockaddr *, int);
__extern int connect(int, const struct sockaddr *, socklen_t);
__extern int listen(int, int);
__extern int accept(int, struct sockaddr *, socklen_t *);
__extern int accept4(int, struct sockaddr *, socklen_t *, int);
__extern int getsockname(int, struct sockaddr *, socklen_t *);
__extern int getpeername(int, struct sockaddr *, socklen_t *);
__extern int socketpair(int, int, int, int *);
__extern int send(int, const void *, size_t, unsigned int);
__extern int sendto(int, const void *, size_t, int, const struct sockaddr *,
			socklen_t);
__extern int recv(int, void *, size_t, unsigned int);
__extern int recvfrom(int, void *, size_t, unsigned int, struct sockaddr *,
			  socklen_t *);
__extern int shutdown(int, int);
__extern int setsockopt(int, int, int, const void *, socklen_t);
__extern int getsockopt(int, int, int, void *, socklen_t *);
__extern int sendmsg(int, const struct msghdr *, unsigned int);
__extern int recvmsg(int, struct msghdr *, unsigned int);

#endif				/* _SYS_SOCKET_H */
