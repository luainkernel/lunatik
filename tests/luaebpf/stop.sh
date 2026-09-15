#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what `lunatik stop` takes down, and what the next `lunatik run` finds.
#   - a stop leaves nothing under the script's root, nothing on the device and no runtime
#   - a run after a stop pins and attaches again, which the first would refuse if the stop had
#     only scheduled the detach
#   - a run over the root a crashed run left behind removes it rather than adopting its maps:
#     the case pins a map of the declared name with a capacity the program file does not
#     declare, which libbpf refuses to reuse, so the run succeeds only by removing it first
#   - a run over a script that is still running is refused with the live one untouched: the
#     root is what the attached program hangs from, so removing it before the runtime refuses
#     the run would take the live deployment down
#   - a run over a root no runtime holds redeploys it: a program with no kernel script has
#     nothing in `lunatik list` to refuse a second run, so the run takes the old program off
#     the device itself, and the new program id the device reports is what proves it
#   - a stop of a name that is only the parent path of a live root leaves that root alone: the
#     CLI derives the path from the name it is given, and nothing under `/sys/fs/bpf/lunatik/`
#     says a directory holding other scripts' roots is a deployment of its own
#   - a stop named with the `.lua` the runner drops takes the deployment down all the same: the
#     runtime is registered under the trimmed name, so the root has to be derived from that one
#   - a stop of a name no pin root can be derived from still reaches the runtime: such a script
#     has no root to take down, and refusing the name would leave it running with no way to stop
#
# Usage: sudo bash tests/luaebpf/stop.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

trap cleanup EXIT

luaebpf_start 8
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

output=$(luaebpf_install loader) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }

output=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the stop is measured against failed"; }
output=$(lunatik stop tests/luaebpf/loader 2>&1)
status=$?
left=$(ls "$LUAEBPF_ROOT" 2>/dev/null | tr '\n' ' ')
listed=$(lunatik list)
attached=$(bpftool net show dev "$LUAEBPF_DEV" | sed -n 2p)

[ "$status" -eq 0 ] || { comment "$output"; fail "luaebpf: the stop exited $status"; }
[ -z "$left" ] || fail "luaebpf: the stop left '$left' under $LUAEBPF_ROOT"
[ -z "$attached" ] || fail "luaebpf: the stop left '$attached' on $LUAEBPF_DEV"
case "$listed" in
*tests/luaebpf/loader*) fail "luaebpf: the stop left the runtime registered" ;;
esac
ktap_pass "luaebpf: a stop unpins the link, stops the runtime and removes the root"

output=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | sort | tr '\n' ' ')
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$output" ] \
	|| { comment "$output"; fail "luaebpf: the run after a stop exited $status"; }
[ "$pinned" = "counts loader-link " ] || fail "luaebpf: the second run's root holds '$pinned'"
ktap_pass "luaebpf: a run after a stop pins and attaches again"

mkdir -p "$LUAEBPF_ROOT/loader"
bpftool map create "$LUAEBPF_ROOT/loader/counts" type array key 4 value 8 entries 1 name counts \
	|| fail "luaebpf: the case could not pin a stale map"
output=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
status=$?
entries=$(bpftool map show pinned "$LUAEBPF_ROOT/loader/counts" 2>/dev/null \
	| grep -oP 'max_entries \K[0-9]+')
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$output" ] \
	|| { comment "$output"; fail "luaebpf: the run over a stale root exited $status"; }
[ "$entries" = "4" ] || fail "luaebpf: the run kept a map of $entries entries, not the declared 4"
ktap_pass "luaebpf: a run removes the root a crashed run left rather than adopting its maps"

output=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the refusal is measured against failed"; }
again=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | sort | tr '\n' ' ')
attached=$(bpftool net show dev "$LUAEBPF_DEV" | sed -n 2p)
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -ne 0 ] || { comment "$again"; fail "luaebpf: a second run of a running script exited 0"; }
echo "$again" | grep -q "is already running" \
	|| { comment "$again"; fail "luaebpf: the refusal does not say the script is already running"; }
[ "$pinned" = "counts loader-link " ] || fail "luaebpf: the refused run left the live root holding '$pinned'"
[ -n "$attached" ] || fail "luaebpf: the refused run took the program off $LUAEBPF_DEV"
ktap_pass "luaebpf: a run over a script already running is refused with the live one untouched"

output=$(luaebpf_install alone) || { comment "$output"; fail "luaebpf: alone.bpf.lua did not compile"; }

output=$(lunatik run tests/luaebpf/alone dev="$LUAEBPF_DEV" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the redeploy is measured against failed"; }
first=$(bpftool net show dev "$LUAEBPF_DEV" | grep -oP 'driver id \K[0-9]+')
again=$(lunatik run tests/luaebpf/alone dev="$LUAEBPF_DEV" 2>&1)
status=$?
second=$(bpftool net show dev "$LUAEBPF_DEV" | grep -oP 'driver id \K[0-9]+')
pinned=$(ls "$LUAEBPF_ROOT/alone" 2>/dev/null | tr '\n' ' ')
lunatik stop tests/luaebpf/alone > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$again" ] \
	|| { comment "$again"; fail "luaebpf: the run over a live root exited $status"; }
[ "$pinned" = "alone-link " ] || fail "luaebpf: the redeployed root holds '$pinned'"
[ -n "$second" ] && [ "$second" != "$first" ] \
	|| fail "luaebpf: $LUAEBPF_DEV carries program '$second', where the first run left '$first'"
ktap_pass "luaebpf: a run over a root no runtime holds takes the old program off the device"

output=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the parent stop is measured against failed"; }
parent=$(lunatik stop tests/luaebpf 2>&1)
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | sort | tr '\n' ' ')
attached=$(bpftool net show dev "$LUAEBPF_DEV" | sed -n 2p)
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$pinned" = "counts loader-link " ] \
	|| { comment "$parent"; fail "luaebpf: the stop of a parent path left the live root holding '$pinned'"; }
[ -n "$attached" ] \
	|| { comment "$parent"; fail "luaebpf: the stop of a parent path took the program off $LUAEBPF_DEV"; }
ktap_pass "luaebpf: a stop of a name that only parents a live root leaves it alone"

output=$(lunatik run tests/luaebpf/loader dev="$LUAEBPF_DEV" 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the suffixed stop is measured against failed"; }
suffixed=$(lunatik stop tests/luaebpf/loader.lua 2>&1)
left=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | sort | tr '\n' ' ')
attached=$(bpftool net show dev "$LUAEBPF_DEV" | sed -n 2p)
listed=$(lunatik list)
lunatik stop tests/luaebpf/loader > /dev/null 2>&1
rm -rf "${LUAEBPF_ROOT:?}/loader"

[ -z "$left" ] || { comment "$suffixed"; fail "luaebpf: the suffixed stop left '$left' under the root"; }
[ -z "$attached" ] || { comment "$suffixed"; fail "luaebpf: the suffixed stop left '$attached' on $LUAEBPF_DEV"; }
case "$listed" in
*tests/luaebpf/loader*) comment "$suffixed"; fail "luaebpf: the suffixed stop left the runtime registered" ;;
esac
ktap_pass "luaebpf: a stop named with the .lua the runner drops takes the deployment down"

output=$(lunatik run ./tests/luaebpf/plain 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the unrooted stop is measured against failed"; }
unrooted=$(lunatik stop ./tests/luaebpf/plain 2>&1)
status=$?
listed=$(lunatik list)
lunatik stop ./tests/luaebpf/plain > /dev/null 2>&1

[ "$status" -eq 0 ] || { comment "$unrooted"; fail "luaebpf: the stop of an unrooted name exited $status"; }
case "$listed" in
*tests/luaebpf/plain*) comment "$unrooted"; fail "luaebpf: the stop of an unrooted name left the runtime" ;;
esac
ktap_pass "luaebpf: a stop of a name no pin root can be derived from still reaches the runtime"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

