#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The CLI exits by the status the driver replies with: an operation the kernel
# refuses exits 1 with its message on stderr and nothing on stdout, one it
# serves exits 0.
#
# - a run of a script that does not exist exits 1, its error on stderr;
# - a run of idle.lua exits 0 with nothing on stdout or stderr;
# - a second run of it exits 1, already running, on stderr;
# - list exits 0 and names it, and a stop exits 0 and it is gone from list;
# - the REPL prints a value longer than one read of the CLI whole.
#
# Usage: sudo bash tests/control/status.sh

SCRIPT="tests/control/idle"
MISSING="tests/control/missing"
LONG=10000

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
}
ERR=$(mktemp)
trap 'cleanup; rm -f "$ERR"' EXIT
cleanup

# runs the CLI, keeping its status in $status, its stdout in $out and its stderr in $err
cli() {
	out=$(lunatik "$@" 2>"$ERR")
	status=$?
	err=$(cat "$ERR")
}

ktap_header
ktap_plan 6

mark_dmesg

cli run "$MISSING"
[ "$status" -eq 1 ] && [ -z "$out" ] && [ -n "$err" ] ||
	fail "a run of a missing script exited $status with '$out' on stdout and '$err' on stderr"
ktap_pass "a run of a script that does not exist exits 1 with its error on stderr"

cli run "$SCRIPT"
[ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] ||
	fail "a run exited $status with '$out' on stdout and '$err' on stderr"
ktap_pass "a run exits 0 with nothing on stdout or stderr"

cli run "$SCRIPT"
[ "$status" -eq 1 ] && [ -z "$out" ] && [[ "$err" == *"already running"* ]] ||
	fail "a second run exited $status with '$out' on stdout and '$err' on stderr"
ktap_pass "a second run of a running script exits 1, already running, on stderr"

cli list
[ "$status" -eq 0 ] && [[ "$out" == *"$SCRIPT"* ]] || fail "list exited $status with '$out'"
cli stop "$SCRIPT"
[ "$status" -eq 0 ] || fail "a stop exited $status with '$err'"
cli list
[[ "$out" != *"$SCRIPT"* ]] || fail "a stopped script is still listed: '$out'"
ktap_pass "list exits 0 and names a running script, and a stop exits 0 and removes it"

# readline echoes a piped line to stdout, so the chunk spells its x as \120
value=$(printf 'string.rep("\\120", %d)\n' "$LONG" | lunatik | tr -cd x)
[ "${#value}" -eq "$LONG" ] || fail "a value of $LONG bytes reached the REPL as ${#value}"
ktap_pass "the REPL prints a value longer than one read whole"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

