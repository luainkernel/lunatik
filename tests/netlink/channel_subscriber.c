/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Userspace subscriber for the netlink channel test (see channel.sh): binds to
* a fixed port id (so the kernel can unicast to it) and joins the given generic
* netlink multicast group, then reads until it has seen both the broadcast and
* the unicast message (or a recv times out).
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <linux/netlink.h>
#include <linux/genetlink.h>

#ifndef SOL_NETLINK
#define SOL_NETLINK 270
#endif
#ifndef NLA_TYPE_MASK
#define NLA_TYPE_MASK (~(int)0xC000)
#endif

#define PAYLOAD      1
#define UNICAST_PORT 0x4c554e41 /* must match channel.lua */

/* message classification, accumulated into a bitmask until BOTH are seen */
enum {
	NONE      = 0,
	BROADCAST = 1,
	UNICAST   = 2,
	BOTH      = BROADCAST | UNICAST,
};

/* binds a NETLINK_GENERIC socket to UNICAST_PORT, joins multicast group `grp`,
 * and bounds every recv with a timeout; returns the fd, or -1 on failure */
static int subscribe(int grp)
{
	struct sockaddr_nl addr = { .nl_family = AF_NETLINK, .nl_pid = UNICAST_PORT };
	struct timeval tv = { .tv_sec = 5 };
	int fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_GENERIC);

	if (fd < 0 ||
	    bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    setsockopt(fd, SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, &grp, sizeof(grp)) < 0 ||
	    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv)) < 0) {
		perror("subscribe");
		close(fd);
		return -1;
	}

	return fd;
}

/* prints the channel's PAYLOAD attribute (the single attribute right after the
 * genl header) and returns which message it was; bounds the read by `n` */
static int report(char *buf, ssize_t n)
{
	struct nlmsghdr *nlh = (struct nlmsghdr *)buf;
	struct nlattr *na = (struct nlattr *)((char *)NLMSG_DATA(nlh) + GENL_HDRLEN);
	int len = (int)n - (int)NLMSG_LENGTH(GENL_HDRLEN);

	if (len < (int)NLA_HDRLEN || na->nla_len < NLA_HDRLEN ||
	    (na->nla_type & NLA_TYPE_MASK) != PAYLOAD)
		return NONE;

	int plen = (int)(na->nla_len - NLA_HDRLEN);
	char msg[256];

	plen = MIN(plen, len - (int)NLA_HDRLEN);
	plen = MIN(plen, (int)sizeof(msg) - 1);
	memcpy(msg, (char *)na + NLA_HDRLEN, plen);
	msg[plen] = '\0';
	printf("%s\n", msg);
	fflush(stdout);

	if (strstr(msg, "broadcast"))
		return BROADCAST;
	if (strstr(msg, "unicast"))
		return UNICAST;
	return NONE;
}

int main(int argc, char **argv)
{
	if (argc < 2) {
		fprintf(stderr, "usage: %s <group-id>\n", argv[0]);
		return 1;
	}

	int fd = subscribe((int)strtol(argv[1], NULL, 0));
	if (fd < 0)
		return 1;

	/* the group is joined; the harness waits for this before sending traffic */
	fprintf(stderr, "READY\n");
	fflush(stderr);

	char buf[4096];
	int seen = NONE;
	while (seen != BOTH) {
		ssize_t n = recv(fd, buf, sizeof(buf), 0);
		if (n <= 0)
			break;
		seen |= report(buf, n);
	}

	return seen == BOTH ? 0 : 1;
}

