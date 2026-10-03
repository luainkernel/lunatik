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
#   one, a word after load, unload, reload or status, a second suite given to
#   test, -e without a chunk, a value given to --help, a chunk or -i given with
#   a command, an option on the wrong side of the verb, -c without a context, a
#   value given to --percpu, and a context or percpu given to stop or list each
#   exit 2 with a line naming it and the usage on stderr, and nothing on stdout;
# - -V and --version print the loaded version, "Lunatik <major>.<minor>", exit 0,
#   and with the modules unloaded -V exits 1, not loaded; the modules are loaded
#   again after it;
# - each module status reports as loaded carries as its version the release -V
#   prints: modpost writes the srcversion reload compares only for a module that
#   declares a version, unless the kernel sets CONFIG_MODULE_SRCVERSION_ALL;
# - status prints through a modinfo that takes no option, as OpenWrt's does,
#   what it prints through the host's;
# - status through a modinfo that reads every installed module as another build
#   names each loaded module as not the installed build.
#
# Usage: sudo bash tests/cli/usage.sh

USAGE="usage: lunatik"
STALE=" is not the installed build"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik load 2>/dev/null
	[ -z "$SHIM" ] || rm -rf "$SHIM"
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
ktap_plan 8

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
for verb in load unload reload status; do
	misused "extra operand x" "$verb" x
done
misused "extra operand b" test a b
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
[[ "$version" =~ ^Lunatik\ [0-9]+\.[0-9]+$ ]] || fail "_LUNATIK_VERSION is '$version', not Lunatik <major>.<minor>"
for flag in -V --version; do
	cli "$flag"
	[ "$status" -eq 0 ] && [ "$out" = "$version" ] || fail "lunatik $flag exited $status with '$out', not '$version'"
done
ktap_pass "-V and --version print the loaded version, Lunatik <major>.<minor>, exit 0"

release=${version#Lunatik }
cli status
modules=$(printf '%s\n' "$out" | sed -n 's/ is loaded$//p')
[ -n "$modules" ] || fail "status named no loaded module: '$out'"
for m in $modules; do
	loaded=$(cat "/sys/module/$m/version" 2>/dev/null)
	[ "$loaded" = "$release" ] || fail "$m carries version '$loaded', not '$release'"
done
ktap_pass "each loaded module carries as its version the release -V prints"

cli status
plain=$out
SHIM=$(mktemp -d)
printf '#!/bin/sh\n[ "$#" -eq 1 ] && exec %s "$1"\nexit 1\n' "$(command -v modinfo)" > "$SHIM/modinfo"
chmod +x "$SHIM/modinfo"
PATH="$SHIM:$PATH" cli status
[ "$out" = "$plain" ] || fail "status through a modinfo that takes no option printed '$out', not '$plain'"
ktap_pass "status prints the same through a modinfo that takes no option"

printf '#!/bin/sh\n%s "$@" | sed "s/^srcversion:.*/srcversion: 0/"\n' "$(command -v modinfo)" > "$SHIM/modinfo"
PATH="$SHIM:$PATH" cli status
for m in $modules; do
	printf '%s\n' "$out" | grep -qxF "$m$STALE" || fail "status over another build did not name $m: '$out'"
done
ktap_pass "status names each module modinfo reads as another build"

lunatik unload || fail "the modules did not unload"
cli -V
[ "$status" -eq 1 ] && [ -z "$out" ] && [ "$err" = "lunatik: not loaded" ] ||
	fail "-V with the modules unloaded exited $status with '$out' on stdout and '$err' on stderr"
lunatik load || fail "the modules did not load again"
ktap_pass "-V with the modules unloaded exits 1, not loaded"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

