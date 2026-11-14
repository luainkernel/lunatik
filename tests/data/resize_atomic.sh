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
# vmalloc-backed. A body allocates with GFP_KERNEL, so kvmalloc takes a buffer
# past KMALLOC_MAX_SIZE from vmalloc whatever memory is free; this script writes
# a page past KMALLOC_MAX_SIZE, which lib.sh's kmalloc_max reads from
# /proc/buddyinfo, into resize_atomic_sizes.lua. Growing that buffer asks the
# page allocator for an order past MAX_PAGE_ORDER, which it refuses, and the
# object must keep its size and its bytes. A runtime allocates with GFP_ATOMIC
# only once its script body has returned, so the body hands back a function the
# driver runs through resume().
#
# Usage: sudo bash tests/data/resize_atomic.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"

SCRIPT=tests/data/resize_atomic
SIZES=/lib/modules/lua/tests/data/resize_atomic_sizes.lua

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	rm -f "$SIZES"
}
trap cleanup EXIT
cleanup

printf 'return {vmalloc = %d}\n' "$(( $(kmalloc_max) + $(getconf PAGESIZE) ))" > "$SIZES"

ktap_header
ktap_plan 1

mark_dmesg
run_script "$SCRIPT"
check_dmesg && ktap_pass "data/resize_atomic"

ktap_totals

