/*
 * inet/inet_ntoa.c
 */

#include <stdint.h>
#include <arpa/inet.h>
#include <stdio.h>

char *inet_ntoa(struct in_addr addr)
{
	static char name[16];
	const uint8_t *cp = (const uint8_t *) &addr.s_addr;

	sprintf(name, "%u.%u.%u.%u", cp[0], cp[1], cp[2], cp[3]);
	return name;
}
