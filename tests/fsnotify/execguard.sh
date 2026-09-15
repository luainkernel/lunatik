#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The execguard example refuses the exec of an entry its allowlist does not name,
# and only inside the directory it marks.
#
# The example is the kernel-side script here, run from where examples_install
# puts it, so this test covers what a reader of the README gets rather than a
# copy of it. Its scope is that directory and nothing else, which is what the
# third program proves: the same name, the same bytes, beside it, runs
# while the one inside is refused. The allowed program is checked first, since a
# verdict path that denies everything passes any test that only asserts denials.
#
# The scope is a tmpfs this test mounts at the path the example names, so the
# rule reaches nothing the machine needs and the unmount in the trap takes the
# mark with it even if the script cannot be stopped. perm.sh brings its own
# tmpfs for the probe that asks whether this kernel has the permission hooks.
#
# Usage: sudo bash tests/fsnotify/execguard.sh

SCRIPT="examples/execguard"
SCOPE="/tmp/lunatik-execguard"
OUTSIDE="/tmp/lunatik-execguard-outside"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/perm.sh"

cleanup() {
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$PROBE" 2>/dev/null
	umount "$SCOPE" 2>/dev/null
	umount "$MOUNT" 2>/dev/null
	rm -rf "$SCOPE" "$OUTSIDE" "$SCRATCH"
}
trap cleanup EXIT
cleanup

perm_begin 7 "fsnotify/execguard"

mkdir -p -m 0700 "$SCOPE" "$OUTSIDE"
mount -t tmpfs -o size=1M,mode=0700 lunatik-execguard "$SCOPE" 2>/dev/null
mountpoint -q "$SCOPE" || perm_skip 7 "fsnotify/execguard: no tmpfs for the scope the example marks"

cp /bin/true "$SCOPE/true" || fail "could not copy a program onto the tmpfs"
cp /bin/true "$SCOPE/blocked" || fail "could not copy a program onto the tmpfs"
cp /bin/true "$OUTSIDE/blocked" || fail "could not copy a program outside the scope"

"$SCOPE/blocked" || fail "the copied program does not run before anything marks it"

mark_dmesg
run_script "$SCRIPT"
"$SCOPE/true"
listed=$?
refused=$("$SCOPE/blocked" 2>&1)
status=$?
outside=$("$OUTSIDE/blocked" 2>&1)
outsidestatus=$?
output=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null
"$SCOPE/blocked"
after=$?

[ "$listed" -eq 0 ] || fail "a program the allowlist names did not run (exit $listed)"
ktap_pass "a name the allowlist carries still runs"

[ "$status" -ne 0 ] || fail "the exec of a name outside the allowlist succeeded"
ktap_pass "a name the allowlist does not carry is refused"

grep -qi "not permitted" <<< "$refused" || fail "the refused exec failed with: $refused"
ktap_pass "the refused exec fails with EPERM"

[ "$outsidestatus" -eq 0 ] || fail "the same name outside the scope did not run: $outside"
ktap_pass "the same name outside the marked directory still runs"

grep -qE "execguard: denied blocked to pid [0-9]+" <<< "$output" || \
	fail "the rule did not name what it refused: $(grep -F 'execguard:' <<< "$output")"
ktap_pass "the refusal names the entry and the pid it was refused to"

[ "$after" -eq 0 ] || fail "the refused program did not run after the example was stopped (exit $after)"
ktap_pass "the rule ends with the example that made it"

errs=$(grep -E "\.lua:[0-9]+:" <<< "$output" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

