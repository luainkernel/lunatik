/*
 * inet/inet_ntop.c
 */

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in6.h>

const char *inet_ntop(int af, const void *cp, char *buf, size_t len)
{
	size_t xlen;

	switch (af) {
	case AF_INET:
		{
			const uint8_t *bp = (const uint8_t *)
				&((const struct in_addr *)cp)->s_addr;

			xlen = snprintf(buf, len, "%u.%u.%u.%u",
					bp[0], bp[1], bp[2], bp[3]);
		}
		break;

	case AF_INET6:
		{
			const struct in6_addr *s = (const struct in6_addr *)cp;

			xlen = snprintf(buf, len, "%x:%x:%x:%x:%x:%x:%x:%x",
					ntohs(s->s6_addr16[0]),
					ntohs(s->s6_addr16[1]),
					ntohs(s->s6_addr16[2]),
					ntohs(s->s6_addr16[3]),
					ntohs(s->s6_addr16[4]),
					ntohs(s->s6_addr16[5]),
					ntohs(s->s6_addr16[6]),
					ntohs(s->s6_addr16[7]));
		}
		break;

	default:
		errno = EAFNOSUPPORT;
		return NULL;
	}

	if (xlen > len) {
		errno = ENOSPC;
		return NULL;
	}

	return buf;
}
