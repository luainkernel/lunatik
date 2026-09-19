/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* Userspace consumer for the linkflap example (examples/linkflap/watch.lua):
* joins the "linkflap" generic netlink multicast group and prints each flapping
* event, decoding the interface name and transition count from the attributes.
*
* Build and run:
*   cc -O2 examples/linkflap/subscriber.c -o linkflap-sub
*   GRP=$(genl ctrl get name linkflap | grep -oiE 'ID-0x[0-9a-f]+' | sed 's/^ID-//i')
*   ./linkflap-sub "$GRP"
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/genetlink.h>

#ifndef SOL_NETLINK
#define SOL_NETLINK 270
#endif
#ifndef NLA_TYPE_MASK
#define NLA_TYPE_MASK (~(int)0xC000)
#endif

/* event attribute types; must match examples/linkflap/watch.lua */
#define LINKFLAP_IFNAME 1
#define LINKFLAP_COUNT  2

/* joins the generic netlink multicast group `grp`; returns the fd, or -1 */
static int subscribe(int grp)
{
	struct sockaddr_nl addr = { .nl_family = AF_NETLINK };
	int fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_GENERIC);

	if (fd < 0 ||
	    bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    setsockopt(fd, SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, &grp, sizeof(grp)) < 0) {
		perror("subscribe");
		close(fd);
		return -1;
	}

	return fd;
}

/* decodes one flapping event from the attributes that follow the genl header,
 * bounding every read by the received length `n`, and prints it */
static void report(const char *buf, ssize_t n)
{
	const struct nlmsghdr *nlh = (const struct nlmsghdr *)buf;
	const char *attr = (const char *)NLMSG_DATA(nlh) + GENL_HDRLEN;
	int len = (int)n - (int)NLMSG_LENGTH(GENL_HDRLEN);
	char ifname[64] = "?";
	unsigned int count = 0;

	while (len >= (int)NLA_HDRLEN) {
		const struct nlattr *na = (const struct nlattr *)attr;
		int alen = na->nla_len;
		if (alen < (int)NLA_HDRLEN || alen > len)
			break;

		const char *data = attr + NLA_HDRLEN;
		int plen = alen - (int)NLA_HDRLEN;

		switch (na->nla_type & NLA_TYPE_MASK) {
		case LINKFLAP_IFNAME:
			plen = MIN(plen, (int)sizeof(ifname) - 1);
			memcpy(ifname, data, plen);
			ifname[plen] = '\0';
			break;
		case LINKFLAP_COUNT:
			if (plen >= (int)sizeof(count))
				memcpy(&count, data, sizeof(count));
			break;
		}

		int step = NLA_ALIGN(alen);
		len  -= step;
		attr += step;
	}

	printf("linkflap: %s flapping (%u transitions)\n", ifname, count);
	fflush(stdout);
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

	char buf[4096];
	for (;;) {
		ssize_t n = recv(fd, buf, sizeof(buf), 0);
		if (n < (ssize_t)NLMSG_LENGTH(GENL_HDRLEN))
			break;
		report(buf, n);
	}

	close(fd);
	return 0;
}

