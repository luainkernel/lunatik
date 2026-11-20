#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests what a stop counts, in the map `luaebpf_errors` the object declares, an entry per place, the
# line a stop logs, and what `lunatik bpf --errors` reports of it.
#   - the runs of a program on two CPUs at once, each counting in its own entry, sum to the runs made;
#     skipped on a host with one CPU
#   - the places of count.bpf.lua are its lines, each once in the order the compiler met them: the
#     two reads of one line are one place, which a run that stops at either counts, and the division
#     and the modulo of one line are two
#   - a function two programs call is one place, which a stop of each program counts; the file
#     names it `luaebpf_errors`, and the object, which keeps that name for the map, loads with the
#     function under another
#   - a program file that stops nowhere declares no map to count in, and no section of lines
#   - a program file that stops nowhere keeps the name `luaebpf_errors` all the same: its program of
#     that name takes `luaebpf_error_2` and its function `luaebpf_error_3`, as a second and a third
#     function of one name do; `lunatik run` pins the program's link as `luaebpf_error_2-link`, and
#     `lunatik bpf --errors` prints nothing and exits 0, the root pinning no map to count in
#   - `lunatik run` pins the map of the counts and the lines of the places beside the program's link
#   - `lunatik bpf --errors` prints nothing before a stop, then the count of the place that
#     stopped, 1 and then 2, and the line it logs, its file, line and reason, and not the place that
#     did not stop; the program is run by the id the device carries, on a frame of the Ethernet
#     header alone, which no frame the device receives is
#   - a second run starts every count at zero
#   - a stop takes the pins down with the root, and `--errors` then exits 1, nothing running; with
#     `-o`, `--btf` or `--scripts`, with a second script, or with no script, it exits 2 with the
#     usage
# Every case after the first reads the counts as the first does, through the reader `--errors`
# calls.
#
# Usage: sudo bash tests/luaebpf/count.sh

DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../lib.sh"
source "$DIR/common.sh"

LUAEBPF_RUNS="stopper nowhere"
trap cleanup EXIT

luaebpf_start 10
luaebpf_device || fail "luaebpf: the case could not create $LUAEBPF_DEV"

BOUNDS="out of bounds"             # luadata_checkbounds, lib/luadata.c
DIVIDE="attempt to divide by zero" # luaV_idiv, lua/lvm.c
MODULO="attempt to perform 'n%0'"  # luaV_mod
RUNS=1000

# frames of 15 and 16 bytes past the one luaebpf_start writes, of 14: the byte past the Ethernet
# header, and the two, 0 and 1, then 1 and 0
printf '\x00' | cat "$LUAEBPF_WORK/packet.bin" - > "$LUAEBPF_WORK/fifteen.bin"
printf '\x00\x01' | cat "$LUAEBPF_WORK/packet.bin" - > "$LUAEBPF_WORK/zeroone.bin"
printf '\x01\x00' | cat "$LUAEBPF_WORK/packet.bin" - > "$LUAEBPF_WORK/onezero.bin"

# the counts after one run of the program <name> over the frame <frame>.bin, by 1 at the place of
# <line> and by none elsewhere, or what they did
once() {
	local before
	before=$(luaebpf_counts)
	luaebpf_returned pinned "$LUAEBPF_PINS/$1" data_in "$LUAEBPF_WORK/$2.bin" > /dev/null
	luaebpf_counted "$before" "$(luaebpf_counts)" "$3" 1
}

READ=$(luaebpf_logline count "local first, second" "$BOUNDS")
QUOTIENT=$(luaebpf_logline count "SHARE // first % second" "$DIVIDE")
REMAINDER=$(luaebpf_logline count "SHARE // first % second" "$MODULO")
SHARED=$(luaebpf_logline count "return SHARE // n" "$DIVIDE")
CALLER=$(luaebpf_logline count "local n = p:getbyte" "$BOUNDS")

output=$(luaebpf_compile count) || { comment "$output"; fail "luaebpf: count.bpf.lua did not compile"; }
output=$(luaebpf_loadall count) || { comment "$output"; fail "luaebpf: count.bpf.lua did not verify"; }

# the runs of left on each of the first two CPUs at once, each in the entry of its CPU
spread() {
	local cpu before
	before=$(luaebpf_counts)
	for cpu in 0 1; do
		taskset -c "$cpu" bpftool prog run pinned "$LUAEBPF_PINS/left" \
			data_in "$LUAEBPF_WORK/packet.bin" repeat "$RUNS" > /dev/null 2>&1 &
	done
	wait
	luaebpf_counted "$before" "$(luaebpf_counts)" "$SHARED" $((RUNS * 2))
}

if [ "$(nproc)" -lt 2 ] || ! command -v taskset > /dev/null; then
	ktap_skip "luaebpf: the host has one CPU, or no taskset"
else
	output=$(spread)
	[ -z "$output" ] || { comment "$output"; fail "luaebpf: the runs on two CPUs did not sum"; }
	ktap_pass "luaebpf: $RUNS stops on each of two CPUs at once count $((RUNS * 2))"
fi

places=$(luaebpf_counts | cut -f2-)
expected="$READ
$QUOTIENT
$REMAINDER
$SHARED
$CALLER"
[ "$places" = "$expected" ] || { comment "$places"; fail "luaebpf: the places are not each line once, in order"; }
output=$(once lines packet "$READ"; once lines fifteen "$READ"; once lines zeroone "$QUOTIENT"
	once lines onezero "$REMAINDER")
[ -z "$output" ] || { comment "$output"; fail "luaebpf: a stop of lines did not count at its place"; }
ktap_pass "luaebpf: two checks of one line count at one place, and two reasons on one line at two"

output=$(once left packet "$SHARED"; once right packet "$SHARED")
[ -z "$output" ] ||
	{ comment "$output"; fail "luaebpf: a stop in a function two programs call did not count once each"; }
ktap_pass "luaebpf: a function two programs call counts the stops of both at its one place"

output=$(luaebpf_compile pass) || { comment "$output"; fail "luaebpf: pass.bpf.lua did not compile"; }
bpftool btf dump file "$LUAEBPF_WORK/pass.bpf.o" | grep -qF "'luaebpf_errors'" &&
	fail "luaebpf: a program file that stops nowhere declares a map to count in"
grep -qaF ".data.luaebpf_errors" "$LUAEBPF_WORK/pass.bpf.o" &&
	fail "luaebpf: a program file that stops nowhere carries the lines of places"
ktap_pass "luaebpf: a program file that stops nowhere declares no map to count in"

output=$(luaebpf_stage nowhere) || { comment "$output"; fail "luaebpf: nowhere.bpf.lua did not compile"; }
functions=$(bpftool btf dump file "$LUAEBPF_WORK/nowhere.bpf.o" | grep -oP "FUNC '\K[^']+(?=' .*linkage=)" |
	tr '\n' ' ')
output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/nowhere 2>&1)
ran=$?
pinned=$(ls "$LUAEBPF_ROOT/nowhere" 2>/dev/null | tr '\n' ' ')
cli bpf --errors tests/luaebpf/nowhere
lunatik stop tests/luaebpf/nowhere > /dev/null 2>&1
[ "$functions" = "luaebpf_error_2 luaebpf_error_3 " ] ||
	fail "luaebpf: a program file that stops nowhere names '$functions'"
[ "$ran" -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: the run of nowhere exited $ran"; }
[ "$pinned" = "luaebpf_error_2-link " ] || fail "luaebpf: the root of nowhere holds '$pinned'"
[ "$status" -eq 0 ] && [ -z "$out$err" ] ||
	{ comment "$out$err"; fail "luaebpf: --errors of a program that stops nowhere exited $status"; }
ktap_pass "luaebpf: a program file that stops nowhere keeps the name luaebpf_errors, pins its link, and reports nothing"

ROOT="$LUAEBPF_ROOT/stopper"
STOPPED=$(luaebpf_logline stopper "local kind" "$BOUNDS")

output=$(luaebpf_stage stopper) || { comment "$output"; fail "luaebpf: stopper.bpf.lua did not compile"; }
output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/stopper 2>&1)
status=$?
pinned=$(ls "$ROOT" 2>/dev/null | tr '\n' ' ')
[ "$status" -eq 0 ] && [ -z "$output" ] || { comment "$output"; fail "luaebpf: the run of stopper exited $status"; }
[ "$pinned" = "luaebpf_errors luaebpf_errors-lines stopper-link " ] || fail "luaebpf: the root of stopper holds '$pinned'"
ktap_pass "luaebpf: lunatik run pins the counts and the lines of the places beside the link"

# what --errors prints after <runs> runs of the program the device carries, on the frame of 14 bytes
reported() {
	local id
	id=$(luaebpf_attached)
	for _ in $(seq "$1"); do
		luaebpf_returned id "$id" data_in "$LUAEBPF_WORK/packet.bin" > /dev/null
	done
	lunatik bpf --errors tests/luaebpf/stopper 2>&1
}

none=$(reported 0)
one=$(reported 1)
two=$(reported 1)
[ -z "$none" ] || { comment "$none"; fail "luaebpf: --errors printed a place before any stop"; }
[ "$one" = "1 $STOPPED" ] || { comment "$one"; fail "luaebpf: --errors did not report one error"; }
[ "$two" = "2 $STOPPED" ] || { comment "$two"; fail "luaebpf: --errors did not report two errors"; }
ktap_pass "luaebpf: lunatik bpf --errors reports the place that stopped, by its line, and no other"

output=$(lunatik run --dev="$LUAEBPF_DEV" tests/luaebpf/stopper 2>&1)
again=$(lunatik bpf --errors tests/luaebpf/stopper 2>&1)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: the second run of stopper failed"; }
[ -z "$again" ] || { comment "$again"; fail "luaebpf: a second run kept the counts of the first"; }
ktap_pass "luaebpf: a second run starts every count at zero"

lunatik stop tests/luaebpf/stopper > /dev/null 2>&1
left=$(ls -d "$ROOT" 2>/dev/null)
cli bpf --errors tests/luaebpf/stopper
[ -z "$left" ] || fail "luaebpf: the stop left $left"
[ "$status" -eq 1 ] && [ -z "$out" ] && [ "$err" = "lunatik: tests/luaebpf/stopper has no compiled program running" ] ||
	{ comment "$err"; fail "luaebpf: --errors of a script nothing runs exited $status"; }
ktap_pass "luaebpf: a stop takes the counts down with the root, and --errors then exits 1"

# each wrong use of --errors that does not exit 2 with the usage: the options a compile alone takes,
# a second script, and no script
misused() {
	local use
	for use in "-o $LUAEBPF_WORK/stopper.o $1" "--btf=/sys/kernel/btf/vmlinux $1" "--scripts=$LUAEBPF_WORK $1" \
		"$1 $1" ""; do
		# shellcheck disable=SC2086 # a use is the words of one command line
		cli bpf --errors $use
		[ "$status" -eq 2 ] && grep -qF "usage:" <<< "$err" || echo "--errors $use exited $status: $err"
	done
}

output=$(misused tests/luaebpf/stopper)
[ -z "$output" ] || { comment "$output"; fail "luaebpf: a wrong use of --errors did not exit 2 with the usage"; }
ktap_pass "luaebpf: --errors with -o, or with no script, exits 2 with the usage"

check_dmesg
ktap_totals
[ $KTAP_FAIL -eq 0 ]

