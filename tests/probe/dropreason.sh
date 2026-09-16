#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Covers the two halves of probing the kernel's drop path, which move together:
# which symbol carries it, and which argument of that symbol is the reason. At
# v6.11 kfree_skb_reason(skb, reason) became a static inline over
# sk_skb_reason_drop(sk, skb, reason), so the name is gone from kallsyms on a
# current kernel and the reason sits one argument to the right. Reading the wrong
# one raises nothing: the handler gets the skb pointer where a reason should be,
# and counts the drop under a name its reason never carried, NOT_DROPPED_YET for
# the NULL that kfree_skb(NULL) passes and UNKNOWN for the rest.
#
# The script resolves its target with linux.lookup and prints it, and this checks
# that name against /proc/kallsyms rather than against a copy of the preference
# order, so a case cannot pass by agreeing with the bug. It then sends BATCH
# datagrams to a closed UDP port, which udp_rcv drops with NO_SOCKET, and the
# script reports only once it has counted BATCH of them: one stray NO_SOCKET from
# the rest of the host is likely, BATCH inside the window is not, and a handler
# reading the wrong argument counts none.
#
# examples/dropreason/monitor.lua picks its target the same way.
#
# Usage: sudo bash tests/probe/dropreason.sh

SCRIPT="tests/probe/dropreason"
BATCH=16   # must match BATCH in dropreason.lua
PORT=59999 # nothing listens here, so every datagram is dropped

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

skip_all() {
	for what in symbol reason; do
		ktap_skip "dropreason/$what: $1"
	done
	ktap_totals
	exit 0
}

CONFIG=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)
# lunatik_lookup reaches kallsyms_lookup_name through a kprobe, and the argument closure needs its own API
for option in CONFIG_KPROBES CONFIG_HAVE_FUNCTION_ARG_ACCESS_API; do
	if [ -n "$CONFIG" ] && ! grep -q "^$option=y" <<< "$CONFIG"; then
		skip_all "needs $option"
	fi
done

grep -qE ' [Tt] (sk_skb_reason_drop|kfree_skb_reason)$' /proc/kallsyms ||
	skip_all "needs sk_skb_reason_drop or kfree_skb_reason"

# a listener on the port takes the datagrams instead of letting them drop
if command -v ss > /dev/null && [ -n "$(ss -uHln "sport = :$PORT" 2>/dev/null)" ]; then
	skip_all "needs UDP port $PORT free"
fi

mark_dmesg
run_script "$SCRIPT" hardirq
for _ in $(seq $BATCH); do
	echo x > "/dev/udp/127.0.0.1/$PORT" || fail "the shell could not send a datagram to 127.0.0.1:$PORT"
done
sleep 1
lunatik stop "$SCRIPT" > /dev/null 2>&1
check_dmesg || { ktap_totals; exit 1; }

symbol=$(dmesg_since | sed -n 's/.*probe dropreason: symbol //p' | tail -1)
[ -n "$symbol" ] || fail "the script never reported the symbol it probed"
grep -qE " [Tt] $symbol\$" /proc/kallsyms || fail "$symbol is not a text symbol of the running kernel"
ktap_pass "the probe goes on a drop path symbol this kernel carries"

dmesg_since | grep -qF "probe dropreason: reason" ||
	fail "the handler never read NO_SOCKET off $BATCH datagrams to a closed port"
ktap_pass "the handler reads the drop reason from the argument that carries it"

ktap_totals

