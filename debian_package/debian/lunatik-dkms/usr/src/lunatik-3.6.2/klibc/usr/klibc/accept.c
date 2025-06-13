/*
 * accept.c
 *
 * Some architectures need to wrap the system call
 */

#include <sys/socket.h>

#if !_KLIBC_SYS_SOCKETCALL && defined(__NR_accept4) && !defined(__NR_accept)

int accept(int socket, struct sockaddr *address, socklen_t *addr_len)
{
	return accept4(socket, address, addr_len, 0);
}

#endif
