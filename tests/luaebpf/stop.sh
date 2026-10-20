#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what `lunatik stop` takes down, and what the next `lunatik run` finds.
#   - a stop leaves no root, no directory above it that held only the root, no runtime, and nothing
#     on the device even while another pin holds the link: removing the root's pin alone would leave
#     that link attached, so the program is off the device only because the stop detached it
#   - a run after a stop pins and attaches again
#   - a run over the root a crashed run left removes it rather than adopting its maps: the case
#     pins a map of the declared name with a capacity the program file does not declare, which
#     libbpf refuses to reuse, so the run succeeds only by removing it first
#   - a run of a script still running is refused, with its root and its program untouched: the
#     root is what the program hangs from, and removing it before the runtime refused the run
#     would take the live one down
#   - a run spelled with a doubled slash and a stop spelled with a leading one leave a live run
#     alone: the runner registers a name as spelled, so neither finds the live one running, while
#     both spell its root
#   - a run over a root no runtime holds redeploys it: a program with no kernel script has nothing
#     in `lunatik list` to refuse a second run, so the run takes the old program off the device
#     itself, and the new program id the device reports is what proves it
#   - a stop of a name that only parents a live root is a stop of nothing: it exits 1, not running,
#     and leaves that root and its program alone
#   - a stop named with the ".lua" the runner drops takes the deployment down all the same: the
#     runtime is registered under the trimmed name, so the root comes from that one
#   - a stop of a name that climbs out of the pins path removes nothing where it lands: a name with
#     a dot has no root, and the stop exits 1, not running
#
# Usage: sudo bash tests/luaebpf/stop.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="loader alone"
trap cleanup EXIT

luaebpf_start 9
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"
output=$(luaebpf_stage loader) || { comment "$output"; fail "luaebpf: loader.bpf.lua did not compile"; }

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the stop is measured against failed"; }
bpftool link pin pinned "$LUAEBPF_ROOT/loader/loader-link" "$LUAEBPF_PINS/held" ||
	fail "luaebpf: the case could not pin the link a second time"
output=$(lunatik stop tests/luaebpf/loader 2>&1)
status=$?
left=$(ls "$LUAEBPF_ROOT" 2>/dev/null | tr '\n' ' ')
listed=$(lunatik list)
attached=$(luaebpf_attached)
rm -f "$LUAEBPF_PINS/held"

[ "$status" -eq 0 ] || { comment "$output"; fail "luaebpf: the stop exited $status"; }
[ -e "$LUAEBPF_ROOT" ] && fail "luaebpf: the stop left $LUAEBPF_ROOT, holding '$left'"
[ -z "$attached" ] || fail "luaebpf: the stop left program $attached on $LUAEBPF_DEV"
grep -qxF tests/luaebpf/loader <<< "$listed" && fail "luaebpf: the stop left the runtime registered"
ktap_pass "luaebpf: a stop detaches the link, stops the runtime and removes the root and its empty parent"

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | tr '\n' ' ')
attached=$(luaebpf_attached)
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: the run after a stop exited $status"; }
[ "$pinned" = "counts loader-link " ] && [ -n "$attached" ] ||
	fail "luaebpf: the run after a stop left '$pinned' and program '$attached'"
ktap_pass "luaebpf: a run after a stop pins and attaches again"

mkdir -p "$LUAEBPF_ROOT/loader"
bpftool map create "$LUAEBPF_ROOT/loader/counts" type array key 4 value 8 entries 1 name counts ||
	fail "luaebpf: the case could not pin a stale map"
output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
status=$?
entries=$(bpftool map show pinned "$LUAEBPF_ROOT/loader/counts" 2>/dev/null | grep -oP 'max_entries \K[0-9]+')
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$output" ] ||
	{ comment "$output"; fail "luaebpf: the run over a stale map exited $status"; }
[ "$entries" = "4" ] || fail "luaebpf: the run kept a map of '$entries' entries, not the declared 4"
ktap_pass "luaebpf: a run removes the root a crashed run left rather than adopting its maps"

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the refusal is measured against failed"; }
first=$(luaebpf_attached)
again=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | tr '\n' ' ')
attached=$(luaebpf_attached)
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 1 ] && grep -qF "is already running" <<< "$again" ||
	{ comment "$again"; fail "luaebpf: a second run of a running script exited $status"; }
[ "$pinned" = "counts loader-link " ] || fail "luaebpf: the refused run left the live root holding '$pinned'"
[ -n "$first" ] && [ "$attached" = "$first" ] ||
	fail "luaebpf: the refused run left program '$attached' where the live run attached '$first'"
ktap_pass "luaebpf: a run of a script already running is refused with the live one untouched"

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the respelled names are measured against failed"; }
first=$(luaebpf_attached)
again=$(lunatik run --dev="$LUAEBPF_DEV" tests//luaebpf/loader 2>&1)
ran=$?
respelled=$(lunatik stop /tests/luaebpf/loader 2>&1)
halted=$?
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | tr '\n' ' ')
attached=$(luaebpf_attached)
listed=$(lunatik list | grep -c 'luaebpf/loader$')
lunatik stop tests/luaebpf/loader tests//luaebpf/loader > /dev/null 2>&1

[ "$ran" -eq 1 ] && grep -qF "no empty component" <<< "$again" ||
	{ comment "$again"; fail "luaebpf: a run of a live script's name spelled with a doubled slash exited $ran"; }
[ "$halted" -eq 1 ] ||
	{ comment "$respelled"; fail "luaebpf: a stop of a live script's name spelled with a leading slash exited $halted"; }
[ "$pinned" = "counts loader-link " ] && [ -n "$first" ] && [ "$attached" = "$first" ] ||
	fail "luaebpf: the respelled names left '$pinned' and program '$attached' where the live run attached '$first'"
[ "$listed" -eq 1 ] || fail "luaebpf: the respelled names left $listed runtimes of the script"
ktap_pass "luaebpf: a run and a stop of a live script's name spelled another way leave it alone"

output=$(luaebpf_stage alone) || { comment "$output"; fail "luaebpf: alone.bpf.lua did not compile"; }
output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/alone 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the redeploy is measured against failed"; }
first=$(luaebpf_attached)
again=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/alone 2>&1)
status=$?
second=$(luaebpf_attached)
pinned=$(ls "$LUAEBPF_ROOT/alone" 2>/dev/null | tr '\n' ' ')
lunatik stop tests/luaebpf/alone > /dev/null 2>&1

[ "$status" -eq 0 ] && [ -z "$again" ] || { comment "$again"; fail "luaebpf: the redeploy exited $status"; }
[ "$pinned" = "alone-link " ] || fail "luaebpf: the redeployed root holds '$pinned'"
[ -n "$second" ] && [ "$second" != "$first" ] ||
	fail "luaebpf: $LUAEBPF_DEV carries program '$second', where the first run left '$first'"
ktap_pass "luaebpf: a run over a root no runtime holds takes the old program off the device"

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the parent stop is measured against failed"; }
parent=$(lunatik stop tests/luaebpf 2>&1)
status=$?
pinned=$(ls "$LUAEBPF_ROOT/loader" 2>/dev/null | tr '\n' ' ')
attached=$(luaebpf_attached)
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 1 ] && grep -qF "tests/luaebpf is not running" <<< "$parent" ||
	{ comment "$parent"; fail "luaebpf: the stop of a parent path exited $status"; }
[ "$pinned" = "counts loader-link " ] && [ -n "$attached" ] ||
	fail "luaebpf: the stop of a parent path left '$pinned' and program '$attached'"
ktap_pass "luaebpf: a stop of a name that only parents a live root leaves it alone"

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/loader 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the run the suffixed stop is measured against failed"; }
suffixed=$(lunatik stop tests/luaebpf/loader.lua 2>&1)
status=$?
left=$(ls "$LUAEBPF_ROOT" 2>/dev/null | tr '\n' ' ')
attached=$(luaebpf_attached)
listed=$(lunatik list)
lunatik stop tests/luaebpf/loader > /dev/null 2>&1

[ "$status" -eq 0 ] || { comment "$suffixed"; fail "luaebpf: the suffixed stop exited $status"; }
[ -z "$left" ] && [ -z "$attached" ] || fail "luaebpf: the suffixed stop left '$left' and program '$attached'"
grep -qxF tests/luaebpf/loader <<< "$listed" && fail "luaebpf: the suffixed stop left the runtime registered"
ktap_pass "luaebpf: a stop named with the .lua the runner drops takes the deployment down"

mkdir "$LUAEBPF_WORK/victim" && touch "$LUAEBPF_WORK/victim/kept"
climbing=$(lunatik stop "../../../..$LUAEBPF_WORK/victim" 2>&1)
status=$?
kept=$(ls "$LUAEBPF_WORK/victim" 2>/dev/null)

[ "$status" -eq 1 ] && grep -qF "is not running" <<< "$climbing" ||
	{ comment "$climbing"; fail "luaebpf: the stop of a climbing name exited $status"; }
[ "$kept" = "kept" ] || fail "luaebpf: the stop of a climbing name removed what it landed on"
ktap_pass "luaebpf: a stop of a name that climbs out of the pins path removes nothing there"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

