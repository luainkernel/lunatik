#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for an allocation failure that looked like a success:
# lunatik_realloc() passed LUA_TNONE as the block's old size, so lunatik_alloc()
# read SIZE_MAX there and returned the old pointer whenever the new allocation
# failed. data:resize() then set the new size over the old, smaller buffer, and
# every accessor read past it.
#
# The failure is forced on the branch that reads that old size: a kmalloc from a
# GFP_ATOMIC runtime, which lunatik_cankrealloc() takes only when the buffer is
# vmalloc-backed. The size asked for is past MAX_PAGE_ORDER on the page sizes
# this suite runs on, so the page allocator refuses it, and the object must keep
# its size and its bytes. A runtime allocates with GFP_ATOMIC only once its
# script body has returned, so the body hands back a function the driver runs
# through resume().
#
# Whether a 64 MiB buffer is vmalloc-backed depends on the kernel's page size and
# MAX_PAGE_ORDER, so the test confirms it through VmallocUsed and skips when the
# allocation stayed in kmalloc. VmallocUsed is host-wide: enough unrelated churn
# in the window reads as the buffer, and the run then passes on the krealloc
# branch, where the defect never showed.
#
# Usage: sudo bash tests/data/resize_atomic.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SCRIPT=tests/data/resize_atomic
BUFFER_MIB=48 # three quarters of the buffer, well clear of the noise from other allocations

cleanup() { lunatik stop "$SCRIPT" 2>/dev/null; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

vmalloc_kib() { grep VmallocUsed /proc/meminfo | awk '{print $2}'; }

mark_dmesg
before=$(vmalloc_kib)
run_script "$SCRIPT"
after=$(vmalloc_kib)
delta_mib=$(( (after - before) / 1024 ))

if ! check_dmesg; then
	ktap_totals
	exit 1
elif [ "$delta_mib" -lt "$BUFFER_MIB" ]; then
	ktap_skip "data/resize_atomic: buffer not vmalloc-backed (delta ${delta_mib}MiB), cannot reach the atomic kmalloc"
else
	ktap_pass "data/resize_atomic"
fi

ktap_totals
[ $KTAP_FAIL -eq 0 ]

