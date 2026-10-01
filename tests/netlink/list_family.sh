#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests list{family = ...} on netlink.rt's addr, route and rule: given AF_INET or
# AF_INET6, each lists at least one record and only records of that family,
# where a dump without a family carries both, since lo holds 127.0.0.1 and ::1
# with their local routes and each family has its default rules. A class whose
# header packed the family into another byte would ask for AF_UNSPEC and list
# both. Skips where lo holds no ::1, since a host of one family cannot tell a
# filter from none, and where the kernel keeps no FIB rules of a family
# (CONFIG_IP_MULTIPLE_TABLES, CONFIG_IPV6_MULTIPLE_TABLES), whose dump it refuses.
#
# Usage: sudo bash tests/netlink/list_family.sh

SCRIPT="tests/netlink/list_family"
MODULE="luasocket"
CASES=6

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan "$CASES"

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

skip_all() {
	for _ in $(seq "$CASES"); do ktap_skip "list_family: $1"; done
	ktap_totals
	exit 0
}

ip -6 addr show dev lo 2>/dev/null | grep -q 'inet6 ::1/' || skip_all "lo holds no ::1"
ip -4 rule show > /dev/null 2>&1 && ip -6 rule show > /dev/null 2>&1 || skip_all "the kernel keeps no FIB rules of a family"

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

for class in addr route rule; do
	dmesg | grep -q "netlink list_family: $class inet$" || fail "$class:list{family = AF_INET} listed another family or none"
	ktap_pass "list_family: $class lists only AF_INET records given AF_INET"

	dmesg | grep -q "netlink list_family: $class inet6$" || fail "$class:list{family = AF_INET6} listed another family or none"
	ktap_pass "list_family: $class lists only AF_INET6 records given AF_INET6"
done

ktap_totals

