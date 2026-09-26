#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The CLI's usage and version: what asks for them prints them on stdout and
# exits 0, and what it cannot read exits 2 with the usage on stderr.
#
# - -h and --help print the usage on stdout, exit 0;
# - an unknown option, an unknown command, a verb without its script, list with
#   one, -e without a chunk, a value given to --help, a chunk or -i given with a
#   command, an option on the wrong side of the verb, -c without a context, a
#   value given to --percpu, and a context or percpu given to stop or list each
#   exit 2 with a line naming it and the usage on stderr, and nothing on stdout;
# - -V and --version print the loaded version, exit 0, and with the modules
#   unloaded -V exits 1, not loaded; the modules are loaded again after it.
#
# Usage: sudo bash tests/cli/usage.sh

USAGE="usage: lunatik"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik load 2>/dev/null
}
trap cleanup EXIT
cleanup

# fails unless the CLI exits 2 with the line named and the usage on stderr, and nothing on stdout
misused() {
	local line="$1"
	shift
	cli "$@"
	[ "$status" -eq 2 ] && [ -z "$out" ] && [[ "$err" == *"lunatik: $line"* ]] && [[ "$err" == *"$USAGE"* ]] ||
		fail "lunatik $* exited $status with '$out' on stdout and '$err' on stderr"
}

ktap_header
ktap_plan 5

mark_dmesg

for flag in -h --help; do
	cli "$flag"
	[ "$status" -eq 0 ] && [[ "$out" == "$USAGE"* ]] && [ -z "$err" ] ||
		fail "lunatik $flag exited $status with '$out' on stdout and '$err' on stderr"
done
ktap_pass "-h and --help print the usage on stdout, exit 0"

misused "unknown option -x" -x
misused "unknown command foo" foo
misused "run takes a script" run
misused "list takes no script" list tests/cli/idle
misused "-e takes a value" -e
misused "--help takes no value" --help=x
misused "-e takes no command" -e "return 1" list
misused "-i takes no command" -i list
misused "unknown option -c" -c softirq run tests/cli/idle
misused "unknown option -e" run -e "return 1" tests/cli/idle
misused "-c takes a value" run -c
misused "--percpu takes no value" run --percpu=x tests/cli/idle
misused "stop takes no context and no percpu" stop -p tests/cli/idle
misused "list takes no context and no percpu" list -c softirq
ktap_pass "what the CLI cannot read exits 2 with a line naming it and the usage on stderr"

version=$(lunatik -e "return _LUNATIK_VERSION")
for flag in -V --version; do
	cli "$flag"
	[ "$status" -eq 0 ] && [ "$out" = "$version" ] || fail "lunatik $flag exited $status with '$out', not '$version'"
done
ktap_pass "-V and --version print the loaded version, exit 0"

lunatik unload || fail "the modules did not unload"
cli -V
[ "$status" -eq 1 ] && [ -z "$out" ] && [ "$err" = "lunatik: not loaded" ] ||
	fail "-V with the modules unloaded exited $status with '$out' on stdout and '$err' on stderr"
lunatik load || fail "the modules did not load again"
ktap_pass "-V with the modules unloaded exits 1, not loaded"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

