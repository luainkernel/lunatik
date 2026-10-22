#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests which packets a netfilter hook's mark and mask let reach its callback,
# and which bits a mark it returns sets. LOCAL_OUT hooks, one registered without
# a mark and one with a mark of 0, and two pings to TARGET, one marked MARK and
# one unmarked: the hook without a mark runs for both, and the hook with 0 runs
# for the unmarked one and not for the marked one, since a mark given selects by
# equality, 0 included, and only an absent one lets every packet through. MARK
# holds 1 in a LOW field and 0xe in a HIGH one: a hook registered on 1 under the
# LOW mask runs for the marked ping, whatever HIGH holds, and not for the
# unmarked one, whose LOW is 0; one with the LOW mask and no mark runs for both.
# A later hook, on 0xe under the HIGH mask, returns 0x3c, and a hook after it
# reads REMARKED: HIGH took the 3, and LOW kept the packet's 1 rather than the
# returned 0xc. Each callback reports, with its mark, only a packet sent to
# TARGET, which keeps the host's own traffic out of the log, and the setter
# marks only such a packet; verdict.sh covers a hook whose mark the packet
# carries, and the mark a hook registered without a mask returns.
#
# Usage: sudo bash tests/netfilter/mark.sh

SCRIPT="tests/netfilter/mark"
MODULE="luanetfilter"
PREFIX="netfilter mark: "
TARGET="127.0.0.225"
MARK=225
REMARKED=49 # MARK, 0xe1, with its HIGH field set to 3

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
ktap_plan 9

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

reported field $MARK || fail "a hook registered on its field's value did not run for a packet holding it"
ktap_pass "a hook registered on its field's value runs for a packet holding it, whatever the other field holds"

reported field 0 && fail "a hook registered on its field's value ran for a packet whose field differs"
ktap_pass "a hook registered on its field's value does not run for a packet whose field differs"

{ reported masked $MARK && reported masked 0; } || fail "a hook registered with a mask and no mark did not run for every packet"
ktap_pass "a hook registered with a mask and no mark runs for every packet"

reported after $REMARKED || fail "a mark returned under a mask did not set its bits alone: $(dmesg_since | grep -F "${PREFIX}after")"
ktap_pass "a mark returned under a mask sets the bits of the mask, and the packet keeps the others"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

