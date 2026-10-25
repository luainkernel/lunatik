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
# A thread body raising a bare errno carries no position for the pattern above to match, and
# luathread spells its death and its three benign stops alike, so the level is what parts them.
KTAP_ERRORS_ERR='luathread: \['

mark_dmesg() { dmesg -C 2>/dev/null; }
dmesg_since() { dmesg; }
# check_dmesg [<ERE>]: the lines <ERE> matches are the ones the test provoked on purpose
check_dmesg() {
	local errs
	errs=$(dmesg_since | grep -E "$KTAP_ERRORS" || true)
	errs="$errs$(dmesg --level=err 2>/dev/null | grep -E "$KTAP_ERRORS_ERR" || true)"
	[ -n "$1" ] && errs=$(grep -vE "$1" <<< "$errs" || true)
	[ -z "$errs" ] && return 0
	ktap_fail "no Lua errors, kernel warnings or oopses"
	echo "# $errs"
	return 1
}

comment() { while IFS= read -r line; do echo "# $line"; done <<< "$1"; }

# polls a condition the kernel reaches on another task after the stimulus returns, a deferred
# callback or release: awaited <command...> runs it ten times a second, up to $TRIES times (50)
awaited() { for _ in $(seq "${TRIES:-50}"); do "$@" && return 0; sleep 0.1; done; return 1; }

# a netdevsim device of one port, for a case on an offload veth has not: nsim_add <id> creates it,
# loading the module where it is not, nsim_port <id> names its port and nsim_del <id> undoes both
NSIM="/sys/bus/netdevsim"
NSIM_LOADED=0
nsim_port() { ls "$NSIM/devices/netdevsim$1/net/" 2>/dev/null; }
nsim_hasport() { [ -n "$(nsim_port "$1")" ]; }
nsim_add() {
	{ lsmod | grep -q "^netdevsim " || { modprobe netdevsim 2>/dev/null && NSIM_LOADED=1; }; } &&
		echo "$1 1" > "$NSIM/new_device" 2>/dev/null && awaited nsim_hasport "$1" || return 1
	udevadm settle 2>/dev/null # the port is renamed once udev reads it
	return 0
}
nsim_del() {
	[ -e "$NSIM/devices/netdevsim$1" ] && echo "$1" > "$NSIM/del_device"
	[ "$NSIM_LOADED" = 1 ] && modprobe -r netdevsim 2>/dev/null
}

# builds the C peer <source> into <binary>; fails where there is no gcc or it does not build
build_peer() { command -v gcc > /dev/null 2>&1 && gcc -O2 -o "$2" "$1" 2>/dev/null; }

# the host's byte order, little or big: od reads the bytes 01 00 as 1 only where the low byte comes first
host_order() { [ "$(printf '\001\000' | od -An -td2 | tr -d ' ')" = 1 ] && echo little || echo big; }

# KMALLOC_MAX_SIZE, the page size shifted by the largest page order, the last of the orders
# /proc/buddyinfo lists: kvmalloc takes a block past it from vmalloc whatever memory is free
kmalloc_max() { echo $(( $(getconf PAGESIZE) << ($(awk 'NR == 1 {print NF - 4}' /proc/buddyinfo) - 1) )); }

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

# served_case <description> <command...> passes the case when the command succeeds, and fails it with what the command
# printed when it does not, except where that names an algorithm the kernel serves no provider of, the message
# tests/lib.lua's alloc raises for ENOENT: there the case skips
served_case() {
	local name=$1 output unserved
	shift
	if output=$("$@"); then
		ktap_pass "$name"
	elif unserved=$(grep -o -m 1 'the kernel serves no [^[:space:]]*' <<< "$output"); then
		ktap_skip "$name: $unserved"
	else
		[ -n "$output" ] && echo "$output"
		ktap_fail "$name"
	fi
}

# a call refused with IRQs disabled: probe_refusal <case> <script> <prefix> runs the script in a
# hardirq runtime, whose pre handler on the personality syscall prints "<prefix>refused" when the
# call raises the refusal and "<prefix>" with anything else when it does not, makes the syscall with
# setarch, and passes the case when the handler only refused; skips without CONFIG_KPROBES or setarch
probe_refusal() {
	local name=$1 script=$2 prefix=$3 config refused other errs
	config=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)
	if [ -n "$config" ] && ! grep -q '^CONFIG_KPROBES=y' <<< "$config"; then
		ktap_skip "$name: needs CONFIG_KPROBES"
	elif ! command -v setarch > /dev/null 2>&1; then
		ktap_skip "$name: needs setarch"
	elif run_test --context=hardirq "$script"; then
		setarch "$(uname -m)" -R true > /dev/null 2>&1
		lunatik stop "$script" 2>/dev/null
		refused=$(dmesg_since | grep -cF "${prefix}refused")
		other=$(dmesg_since | grep -F "$prefix" | grep -cvF "${prefix}refused")
		errs=$(dmesg_since | grep -E "$KTAP_ERRORS")
		if [ "$refused" -ge 1 ] && [ "$other" -eq 0 ] && [ -z "$errs" ]; then
			ktap_pass "$name"
		else
			[ -n "$errs" ] && comment "$errs"
			ktap_fail "$name: the handler's call was refused $refused times and went through $other times"
		fi
	else
		ktap_fail "$name"
	fi
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

# errname gives "unknown" for every errno without CONFIG_SYMBOLIC_ERRNAME, and the suites assert the names it gives
errnames() {
	local config
	config=$({ zcat /proc/config.gz || cat "/boot/config-$(uname -r)"; } 2>/dev/null)
	[ -z "$config" ] || grep -q '^CONFIG_SYMBOLIC_ERRNAME=y' <<< "$config"
}

if ! errnames; then
	suite=${0#*tests/}
	suite=${suite%.sh}
	ktap_header
	ktap_plan 1
	ktap_skip "${suite%/run}: errno names need CONFIG_SYMBOLIC_ERRNAME"
	ktap_totals
	exit 0
fi

