#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.channel end to end FROM SOFTIRQ: a softirq runtime registers a
# generic netlink multicast family ("lunatiktest") and a PRE_ROUTING netfilter
# hook that broadcasts on received traffic, which runs in NET_RX softirq. A
# userspace subscriber (built with gcc) joins the family's multicast group and
# receives the payload, proving kernel-to-userspace delivery from softirq.
#
# Usage: sudo bash tests/netlink/channel.sh

SCRIPT="tests/netlink/channel"
MODULE="luanetlink"
FAMILY="lunatiktest"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

SUB_BIN="$(mktemp)"
SUB_OUT="$(mktemp)"
SUB_ERR="$(mktemp)"
cleanup() {
	kill "$SUB_PID" 2>/dev/null
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -f "$SUB_BIN" "$SUB_BIN.c" "$SUB_OUT" "$SUB_ERR"
}
trap cleanup EXIT

ktap_header
ktap_plan 1

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}
command -v gcc > /dev/null 2>&1 || { ktap_skip "channel: gcc unavailable"; ktap_totals; exit 0; }
command -v genl > /dev/null 2>&1 || { ktap_skip "channel: genl tool unavailable"; ktap_totals; exit 0; }

cat > "$SUB_BIN.c" <<'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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
#define PAYLOAD 1

int main(int argc, char **argv)
{
	int grp = (int)strtol(argv[1], NULL, 0);
	int fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_GENERIC);
	if (fd < 0) { perror("socket"); return 2; }
	struct sockaddr_nl addr;
	memset(&addr, 0, sizeof(addr));
	addr.nl_family = AF_NETLINK;
	if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) { perror("bind"); return 2; }
	if (setsockopt(fd, SOL_NETLINK, NETLINK_ADD_MEMBERSHIP, &grp, sizeof(grp)) < 0) { perror("join"); return 2; }
	struct timeval tv = { .tv_sec = 5 };
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	fprintf(stderr, "READY\n");
	fflush(stderr);

	char buf[4096];
	ssize_t n = recv(fd, buf, sizeof(buf), 0);
	if (n <= 0) return 1;
	struct nlmsghdr *nlh = (struct nlmsghdr *)buf;
	struct nlattr *na = (struct nlattr *)((char *)NLMSG_DATA(nlh) + GENL_HDRLEN);
	int len = nlh->nlmsg_len - NLMSG_LENGTH(GENL_HDRLEN);
	while (len >= (int)NLA_HDRLEN) {
		if ((na->nla_type & NLA_TYPE_MASK) == PAYLOAD) {
			printf("%.*s\n", (int)(na->nla_len - NLA_HDRLEN), (char *)na + NLA_HDRLEN);
			return 0;
		}
		int step = NLA_ALIGN(na->nla_len);
		len -= step;
		na = (struct nlattr *)((char *)na + step);
	}
	return 1;
}
EOF
gcc -O2 -o "$SUB_BIN" "$SUB_BIN.c" 2>/dev/null || { ktap_skip "channel: subscriber failed to build"; ktap_totals; exit 0; }

mark_dmesg
run_script "$SCRIPT" softirq
check_dmesg || { ktap_totals; exit 1; }

# the family is now registered; resolve its multicast group id
GRP=$(genl ctrl get name "$FAMILY" 2>/dev/null | grep -A1 'multicast groups' | grep -oE 'ID-0x[0-9a-fA-F]+' | head -1 | sed 's/ID-//')
[ -n "$GRP" ] || fail "could not resolve multicast group for family $FAMILY"

"$SUB_BIN" "$GRP" > "$SUB_OUT" 2> "$SUB_ERR" &
SUB_PID=$!
for _ in $(seq 1 50); do grep -q READY "$SUB_ERR" 2>/dev/null && break; sleep 0.1; done

# generate loopback traffic; the received packet fires PRE_ROUTING in NET_RX softirq
for _ in $(seq 1 5); do echo x > /dev/udp/127.0.0.1/9999 2>/dev/null; sleep 0.1; done

wait "$SUB_PID" 2>/dev/null
check_dmesg || { ktap_totals; exit 1; }
grep -q "netlink channel: ok" "$SUB_OUT" || fail "subscriber did not receive the softirq broadcast"
ktap_pass "channel: userspace received broadcast sent from a softirq netfilter hook"

ktap_totals

