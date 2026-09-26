#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# run, spawn, stop and list exit by what the kernel answered, and a context the
# CLI cannot read never reaches it.
#
# - a run and a spawn of a script that does not exist, and a run of broken.lua,
#   which raises at load, exit 1 with lunatik: and the message on stderr and
#   nothing on stdout;
# - a run of idle.lua exits 0 with nothing on stdout or stderr, and a second
#   run exits 1 with lunatik: and "already running", no position of the runner's;
# - a run with a word that is neither a context nor percpu, and a spawn with any
#   word after its script, exit 2 with the reason and the usage on stderr, and
#   nothing reaches the kernel: list does not name the script;
# - a run named in process context and its stop exit 0;
# - a spawn exits 0 with nothing printed, list exits 0 and names it, and its
#   stop exits 0 and removes it.
#
# Usage: sudo bash tests/cli/verbs.sh

SCRIPT="tests/cli/idle"
BROKEN="tests/cli/broken"
MISSING="tests/cli/missing"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$BROKEN" 2>/dev/null
}
trap cleanup EXIT
cleanup

# fails unless the CLI exits 1 with lunatik: and the message named on stderr, and nothing on stdout
refused() {
	local message="$1"
	shift
	cli "$@"
	[ "$status" -eq 1 ] && [ -z "$out" ] && [[ "$err" == "lunatik: "*"$message"* ]] ||
		fail "lunatik $* exited $status with '$out' on stdout and '$err' on stderr"
}

ktap_header
ktap_plan 6

mark_dmesg

refused "cannot open" run "$MISSING"
refused "cannot open" spawn "$MISSING"
refused "broken" run "$BROKEN"
ktap_pass "a run or a spawn of a missing script, and a run that raises at load, exit 1 with the error on stderr"

cli run "$SCRIPT"
[ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] ||
	fail "a run exited $status with '$out' on stdout and '$err' on stderr"
refused "$SCRIPT is already running" run "$SCRIPT"
[[ "$err" != *"runner.lua"* ]] || fail "the runner's message carries its position: '$err'"
ktap_pass "a run exits 0 with nothing printed, and a second exits 1, already running, with no position"

cli stop "$SCRIPT"
[ "$status" -eq 0 ] || fail "a stop exited $status with '$err'"
for words in "foo" "softirq foo"; do
	cli run "$SCRIPT" $words
	[ "$status" -eq 2 ] && [ -z "$out" ] && [[ "$err" == *"foo is not a context: process, softirq or hardirq"* ]] ||
		fail "lunatik run $SCRIPT $words exited $status with '$out' on stdout and '$err' on stderr"
done
for words in softirq hardirq process percpu foo; do
	cli spawn "$SCRIPT" "$words"
	[ "$status" -eq 2 ] && [ -z "$out" ] && [[ "$err" == *"spawn takes no context and no percpu"* ]] ||
		fail "lunatik spawn $SCRIPT $words exited $status with '$out' on stdout and '$err' on stderr"
done
[[ "$(lunatik list)" != *"$SCRIPT"* ]] || fail "a refused invocation reached the kernel: $SCRIPT is listed"
ktap_pass "a word run cannot read, and a context or percpu given to spawn, exit 2 and reach nothing"

cli run "$SCRIPT" process
[ "$status" -eq 0 ] || fail "a run in process context exited $status with '$err'"
cli stop "$SCRIPT"
[ "$status" -eq 0 ] && [[ "$(lunatik list)" != *"$SCRIPT"* ]] || fail "a stop exited $status and left $SCRIPT listed"
ktap_pass "a run named in process context exits 0, and its stop exits 0 and removes it"

cli spawn "$SCRIPT"
[ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] ||
	fail "a spawn exited $status with '$out' on stdout and '$err' on stderr"
cli list
[ "$status" -eq 0 ] && [[ "$out" == *"$SCRIPT"* ]] || fail "list exited $status with '$out'"
cli stop "$SCRIPT"
[ "$status" -eq 0 ] && [[ "$(lunatik list)" != *"$SCRIPT"* ]] || fail "a stop exited $status and left $SCRIPT listed"
ktap_pass "a spawn exits 0 and is listed, and its stop exits 0 and removes it"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

