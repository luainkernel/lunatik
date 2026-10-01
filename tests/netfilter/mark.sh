#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests which packets a netfilter hook's mark lets reach its callback. Two
# LOCAL_OUT hooks, one registered without a mark and one with a mark of 0, and
# two pings to TARGET, one marked MARK and one unmarked: the hook without a mark
# runs for both, and the hook with 0 runs for the unmarked one and not for the
# marked one, since a mark given selects by equality, 0 included, and only an
# absent one lets every packet through. Each callback reports, with its mark,
# only a packet sent to TARGET, which keeps the host's own traffic out of the
# log; verdict.sh covers a hook whose mark the packet carries.
#
# Usage: sudo bash tests/netfilter/mark.sh

SCRIPT="tests/netfilter/mark"
MODULE="luanetfilter"
PREFIX="netfilter mark: "
TARGET="127.0.0.225"
MARK=225

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
trap cleanup EXIT
cleanup

skip() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

# reported <hook> <mark>: the callback of that hook ran for the ping that carried that mark
reported() {
	dmesg_since | grep -qE "${PREFIX}$1 $2\$"
}

[ -e /sys/module/$MODULE ] || skip "netfilter/mark: $MODULE not loaded"

ktap_header
ktap_plan 5

mark_dmesg
run_script --context=softirq "$SCRIPT"
ping -c 1 -W 1 -m $MARK $TARGET > /dev/null 2>&1 || fail "the marked ping did not go through"
ping -c 1 -W 1 $TARGET > /dev/null 2>&1 || fail "the unmarked ping did not go through"
lunatik stop "$SCRIPT" 2>/dev/null

reported absent $MARK || fail "a hook registered without a mark did not run for a marked packet"
ktap_pass "a hook registered without a mark runs for a marked packet"

reported zero $MARK && fail "a hook registered with a mark of 0 ran for a marked packet"
ktap_pass "a hook registered with a mark of 0 does not run for a marked packet"

reported absent 0 || fail "a hook registered without a mark did not run for an unmarked packet"
ktap_pass "a hook registered without a mark runs for an unmarked packet"

reported zero 0 || fail "a hook registered with a mark of 0 did not run for an unmarked packet"
ktap_pass "a hook registered with a mark of 0 runs for an unmarked packet"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

