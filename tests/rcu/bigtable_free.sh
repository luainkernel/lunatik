#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for freeing a large object private. lunatik_newobject()
# allocates the private through the runtime allocator, which uses kvmalloc for
# big sizes (vmalloc once past the kmalloc order). lunatik_releaseprivate() then
# freed it with kfree(), which faults on a vmalloc'd pointer; the fix frees it
# with kvfree().
#
# The kmalloc/vmalloc threshold depends on the kernel's MAX_ORDER, so the test
# confirms via VmallocUsed that the private is actually vmalloc-backed and skips
# (never false-passes) when the allocation stayed in kmalloc. When it is
# vmalloc-backed, freeing it must leave the kernel alive.
#
# Usage: sudo bash tests/rcu/bigtable_free.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

cleanup() { lunatik stop tests/rcu/bigtable_free 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

vmalloc_kib() { grep VmallocUsed /proc/meminfo | awk '{print $2}'; }

before=$(vmalloc_kib)
run_script tests/rcu/bigtable_free
after=$(vmalloc_kib)
delta_mib=$(( (after - before) / 1024 ))

mark_dmesg
lunatik stop tests/rcu/bigtable_free 2>/dev/null
log=$(dmesg_since)
crash=$(echo "$log" | grep -iE "Oops|BUG: unable|kernel BUG at|unable to handle kernel|mem abort" || true)

if [ -n "$crash" ]; then
	ktap_fail "rcu/bigtable_free: kernel crashed freeing a vmalloc'd private"
	echo "# ${crash%%$'\n'*}"
elif [ "$delta_mib" -lt 16 ]; then
	ktap_skip "rcu/bigtable_free: private not vmalloc-backed (delta ${delta_mib}MiB), cannot exercise kvfree"
else
	ktap_pass "rcu/bigtable_free"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

