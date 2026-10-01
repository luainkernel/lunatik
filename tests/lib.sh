#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# KTAP helpers and lunatik test utilities.
# Source this file from each test script.

KTAP_COUNT=0
KTAP_PASS=0
KTAP_FAIL=0
KTAP_SKIP=0

# the core a result was produced against: a suite read without it can be measuring the
# module a failed build left installed
ktap_header() { echo "KTAP version 1"; echo "# core: $(cat /sys/module/lunatik/srcversion 2>/dev/null || echo "not loaded")"; }
ktap_plan()   { echo "1..$1"; }
ktap_pass()   { KTAP_COUNT=$((KTAP_COUNT+1)); KTAP_PASS=$((KTAP_PASS+1)); echo "ok $KTAP_COUNT $*"; }
ktap_fail()   { KTAP_COUNT=$((KTAP_COUNT+1)); KTAP_FAIL=$((KTAP_FAIL+1)); echo "not ok $KTAP_COUNT $*"; }
ktap_skip()   { KTAP_COUNT=$((KTAP_COUNT+1)); KTAP_SKIP=$((KTAP_SKIP+1)); echo "ok $KTAP_COUNT $* # SKIP"; }
ktap_totals() { echo "# Totals: pass:$KTAP_PASS fail:$KTAP_FAIL skip:$KTAP_SKIP"; [ "$KTAP_FAIL" -eq 0 ]; }

# A Lua error, or a kernel complaint a script's input should not be able to provoke;
# arm64 heads an oops with "Internal error:", and a debug trap nobody owns with the BRK line.
KTAP_ERRORS='(\.lua:[0-9]+|\?:\?):|Lua warning:|WARNING:|UBSAN:|Internal error:|Unexpected kernel BRK'

mark_dmesg() { dmesg -C 2>/dev/null; }
dmesg_since() { dmesg; }
check_dmesg() {
	local errs
	errs=$(dmesg_since | grep -E "$KTAP_ERRORS" || true)
	[ -z "$errs" ] && return 0
	ktap_fail "no Lua errors, kernel warnings or oopses"
	echo "# $errs"
	return 1
}

comment() { while IFS= read -r line; do echo "# $line"; done <<< "$1"; }

# builds the C peer <source> into <binary>; fails where there is no gcc or it does not build
build_peer() { command -v gcc > /dev/null 2>&1 && gcc -O2 -o "$2" "$1" 2>/dev/null; }

# counts how often a function runs: kprobe_place <group>/<event> <symbol> arms a kprobe in a
# tracing instance named for the group, and fails where tracing or the symbol is unavailable;
# kprobe_hits <group>/<event> reads its count from kprobe_profile, misses included, which is how
# the kernel counts a run inside another kprobe's handler; kprobe_remove <group>/<event>
# takes it down, and the instance with it once no event of the group is enabled there
TRACING="/sys/kernel/tracing"
kprobe_place() {
	local instance="$TRACING/instances/${1%%/*}"
	echo "p:$1 $2" >> "$TRACING/kprobe_events" 2>/dev/null &&
		mkdir -p "$instance" 2>/dev/null && echo 1 > "$instance/events/$1/enable" 2>/dev/null
}
kprobe_hits() { awk -v event="${1#*/}" '$1 == event { print $2 + $3 }' "$TRACING/kprobe_profile"; }
kprobe_remove() {
	local instance="$TRACING/instances/${1%%/*}"
	[ -d "$instance" ] && echo 0 > "$instance/events/$1/enable" 2>/dev/null && rmdir "$instance" 2>/dev/null
	grep -q ":$1 " "$TRACING/kprobe_events" 2>/dev/null && echo "-:$1" >> "$TRACING/kprobe_events"
}

# the CLI in a pid namespace of its own, which holds none of the shell's pids: CLI=pidns before
# run_script or run_test runs the script's body from there
pidns() { unshare --pid --fork lunatik "$@"; }

# only in the initial pid namespace, whose inode is PROC_PID_INIT_INO, are the shell's pids the numbers
# task:pid() returns
initpidns() { [ "$(readlink /proc/self/ns/pid)" = "pid:[4026531836]" ]; }

# a script that fails reports its error on the output.
run_script() {
	local output
	output=$(${CLI:-lunatik} run "$@" 2>&1)
	[ -z "$output" ] && return 0
	ktap_fail "Lua error in script"
	comment "$output"
	ktap_totals
	exit 1
}

# Same, for suites that run several scripts and count each one.
run_test() {
	local output errs
	mark_dmesg
	output=$(${CLI:-lunatik} run "$@" 2>&1)
	errs=$(dmesg_since | grep -E "^[^:]+: (FAIL|fail)	|$KTAP_ERRORS" || true)
	[ -z "$output" ] && [ -z "$errs" ] && return 0

	[ -n "$output" ] && comment "$output"
	[ -n "$errs" ] && comment "$errs"
	return 1
}

# runs the CLI, keeping its status in $status, its stdout in $out and its stderr in $err
cli() {
	local errfile
	errfile=$(mktemp)
	out=$(lunatik "$@" 2>"$errfile")
	status=$?
	err=$(cat "$errfile")
	rm -f "$errfile"
}

# Each test script must define cleanup().
# fail <description> stops the script, calls cleanup, and exits non-zero.
fail() {
	ktap_fail "$*"
	echo "# FAIL: $*" >&2
	lunatik stop "${SCRIPT:-}" 2>/dev/null
	cleanup 2>/dev/null || true
	ktap_totals
	exit 1
}

