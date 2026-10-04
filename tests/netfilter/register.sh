#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what netfilter.register refuses in the table it is given, before any
# hook is registered, each with an error naming the field and the type it got:
# a mark that holds a string, a numeric one included, or a boolean, and a pf,
# hooknum or priority that is missing or holds a string. Each of the four is
# refused past its type as well, out of bounds: pf below 0 or past 8 bits,
# hooknum and mark below 0 or past 32, priority past an int, each by a value
# whose low bits a truncating build would register as a hook of its own; a
# family netfilter keeps no hook table for, UNSPEC or NETDEV, is refused naming
# pf, and a hook past its family's table, INGRESS of INET, NUMHOOKS of IPV4, IPV6
# and ARP and BROUTING of BRIDGE, naming hooknum, where nf_hook_entry_head
# (net/netfilter/core.c) would WARN, which run_test reads from dmesg; a mark at
# the top of its range and a priority at either end of an int are accepted.
# The script asks for a LOCAL_OUT hook with each of those from a softirq
# runtime, the context the binding serves; verdict.sh covers the marks that are
# numbers.
#
# Usage: sudo bash tests/netfilter/register.sh

SCRIPT="tests/netfilter/register"
MODULE="luanetfilter"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

[ -e /sys/module/$MODULE ] || skip "netfilter/register: $MODULE not loaded"

ktap_header
ktap_plan 2

run_test --context=softirq "$SCRIPT" || fail "netfilter.register accepted a field it should refuse, or raised something else"
ktap_pass "a mark that is not a number, a required field missing or not a number, and a field past its range are refused, naming the field"

lunatik stop "$SCRIPT" > /dev/null
check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

