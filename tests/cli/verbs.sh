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
# - a context that is not one of the three, as -c or as the word after the
#   script, and a context, percpu or any other word given to spawn, as options
#   or as words, exit 2 with the reason and the usage on stderr, and nothing
#   reaches the kernel: list does not name the script;
# - -c and -p, and --context= and --percpu, run the script in that context and
#   once per CPU id, listed once; -- ends the options before the script;
# - the words after the script still run it, each with a line on stderr naming
#   the option that replaces it;
# - list prints one script a line;
# - a stop of two running scripts exits 0 and removes both; a stop of a script
#   nothing runs exits 1, not running, and of two scripts one of which runs,
#   stops that one and exits 1;
# - a spawn exits 0 with nothing printed, list exits 0 and names it, and its
#   stop exits 0 and removes it.
#
# Usage: sudo bash tests/cli/verbs.sh

SCRIPT="tests/cli/idle"
BROKEN="tests/cli/broken"
OTHER="tests/cli/other"
MISSING="tests/cli/missing"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$OTHER" 2>/dev/null
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
ktap_plan 9

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
for args in "-c foo $SCRIPT" "--context=foo $SCRIPT" "$SCRIPT foo" "$SCRIPT softirq foo"; do
	cli run $args
	[ "$status" -eq 2 ] && [ -z "$out" ] && [[ "$err" == *"foo is not a context: process, softirq or hardirq"* ]] ||
		fail "lunatik run $args exited $status with '$out' on stdout and '$err' on stderr"
done
for args in "-c softirq $SCRIPT" "-p $SCRIPT" "$SCRIPT hardirq" "$SCRIPT process" "$SCRIPT percpu" "$SCRIPT foo"; do
	cli spawn $args
	[ "$status" -eq 2 ] && [ -z "$out" ] && [[ "$err" == *"spawn takes no context and no percpu"* ]] ||
		fail "lunatik spawn $args exited $status with '$out' on stdout and '$err' on stderr"
done
[[ "$(lunatik list)" != *"$SCRIPT"* ]] || fail "a refused invocation reached the kernel: $SCRIPT is listed"
ktap_pass "a context run cannot read, and a context, percpu or any other word given to spawn, exit 2 and reach nothing"

for args in "-c softirq -p" "--context=hardirq --percpu" "-c process --"; do
	cli run $args "$SCRIPT"
	[ "$status" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] ||
		fail "lunatik run $args $SCRIPT exited $status with '$out' on stdout and '$err' on stderr"
	[ "$(lunatik list | grep -cx "$SCRIPT")" -eq 1 ] || fail "lunatik run $args $SCRIPT is not listed once"
	lunatik stop "$SCRIPT" || fail "the script run with $args did not stop"
done
ktap_pass "-c and -p, their long spellings and -- run the script, listed once"

for words in "softirq" "hardirq percpu"; do
	cli run "$SCRIPT" $words
	[ "$status" -eq 0 ] && [ -z "$out" ] || fail "lunatik run $SCRIPT $words exited $status with '$out' and '$err'"
	for word in $words; do
		option="-c $word"
		[ "$word" = percpu ] && option="-p"
		[[ "$err" == *"lunatik: $word after the script is deprecated, use $option"* ]] ||
			fail "lunatik run $SCRIPT $words did not name $option: '$err'"
	done
	lunatik stop "$SCRIPT" || fail "the script run with $words did not stop"
done
ktap_pass "the words after the script still run it, each naming the option that replaces it"

cli run "$SCRIPT"
cli run "$OTHER"
cli list
listed=$(printf '%s\n' "$out" | grep -xF -e "$OTHER" -e "$SCRIPT" | sort)
[ "$status" -eq 0 ] && [ "$listed" = "$(printf '%s\n%s\n' "$OTHER" "$SCRIPT" | sort)" ] ||
	fail "list exited $status with '$out', not one script a line"
ktap_pass "list prints one script a line"

cli stop "$SCRIPT" "$OTHER"
listed=$(lunatik list)
[ "$status" -eq 0 ] && [ -z "$err" ] && [[ "$listed" != *"$SCRIPT"* ]] && [[ "$listed" != *"$OTHER"* ]] ||
	fail "a stop of two running scripts exited $status with '$err' and left '$listed'"
refused "$SCRIPT is not running" stop "$SCRIPT"
lunatik run "$OTHER" || fail "$OTHER did not run again"
refused "$SCRIPT is not running" stop "$SCRIPT" "$OTHER"
[[ "$(lunatik list)" != *"$OTHER"* ]] || fail "a stop of two scripts, one not running, left '$(lunatik list)'"
ktap_pass "a stop removes the running scripts, and a stop of one nothing runs exits 1 after stopping the rest"

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

