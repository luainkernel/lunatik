#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The execguard example refuses the exec of an entry its allowlist does not name,
# and, when the scope holds a pid list, the exec by a pid the list does not name,
# and only inside the directory it marks.
#
# The example is the kernel-side script here, run from where examples_install
# puts it, so this test covers what a reader of the README gets rather than a
# copy of it. Its scope is that directory and nothing else, which is what the
# two more copies prove: the same name, the same bytes, beside it and one level
# below it, run while the one inside is refused. The allowed program is checked
# first, since a verdict path that denies everything passes any test that only
# asserts denials.
#
# A script the allowlist names is refused when its #! names a copy of sh inside
# the scope: the kernel opens the interpreter for exec too, and the rule is
# asked about it under its own name, which is the name the refusal carries.
#
# The pid list is a second run of the example, with the list written into the
# scope before it starts. Three shells wait on a fifo each and exec in place
# once released, so the pid that asks is the one the list was written with; two
# of them are listed. The same allowed program runs for a listed shell and is
# refused to the unlisted one, and a listed shell is still refused a name the
# allowlist does not carry, so the two lists combine rather than one replacing
# the other.
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
WAITERS=""

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/perm.sh"

cleanup() {
	[ -z "$WAITERS" ] || kill $WAITERS 2>/dev/null
	lunatik stop "$SCRIPT" 2>/dev/null
	lunatik stop "$PROBE" 2>/dev/null
	umount "$SCOPE" 2>/dev/null
	umount "$MOUNT" 2>/dev/null
	rm -rf "$SCOPE" "$OUTSIDE" "$SCRATCH"
}
trap cleanup EXIT
cleanup

# waiter <name> <program>: a shell that execs <program> in place once release lets it go
waiter() {
	mkfifo "$SCRATCH/$1" || fail "could not make a fifo for $1"
	( read -r _ < "$SCRATCH/$1"; exec "$2" ) > "$SCRATCH/$1.out" 2>&1 &
}

# release <name> <pid>: returns the exit status of what the waiter ran
release() {
	echo > "$SCRATCH/$1"
	wait "$2"
}

perm_begin 14 "fsnotify/execguard"

mkdir -p -m 0700 "$SCOPE" "$OUTSIDE"
mount -t tmpfs -o size=1M,mode=0700 lunatik-execguard "$SCOPE" 2>/dev/null
mountpoint -q "$SCOPE" || perm_skip 14 "fsnotify/execguard: no tmpfs for the scope the example marks"
mkdir "$SCOPE/sub" || fail "could not make a directory on the tmpfs"

cp /bin/true "$SCOPE/true" || fail "could not copy a program onto the tmpfs"
cp /bin/true "$SCOPE/blocked" || fail "could not copy a program onto the tmpfs"
cp /bin/true "$OUTSIDE/blocked" || fail "could not copy a program outside the scope"
cp /bin/true "$SCOPE/sub/blocked" || fail "could not copy a program below the scope"
cp /bin/sh "$SCOPE/sh" || fail "could not copy an interpreter onto the tmpfs"
printf '#!%s\nexit 0\n' "$SCOPE/sh" > "$SCOPE/false" && chmod +x "$SCOPE/false" || \
	fail "could not write a script onto the tmpfs"

"$SCOPE/blocked" || fail "the copied program does not run before anything marks it"
"$SCOPE/false" || fail "the script does not run before anything marks it"

mark_dmesg
run_script "$SCRIPT"
"$SCOPE/true"
listed=$?
refused=$( { echo "$BASHPID"; exec "$SCOPE/blocked"; } 2>&1 )
status=$?
pid=${refused%%$'\n'*}
outside=$("$OUTSIDE/blocked" 2>&1)
outsidestatus=$?
below=$("$SCOPE/sub/blocked" 2>&1)
belowstatus=$?
interpreted=$("$SCOPE/false" 2>&1)
interpretedstatus=$?
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

[ "$belowstatus" -eq 0 ] || fail "the same name below the marked directory did not run: $below"
ktap_pass "the same name one level below the marked directory still runs"

grep -qF "execguard: denied blocked to pid $pid" <<< "$output" || \
	fail "the rule did not name what it refused to $pid: $(grep -F 'execguard:' <<< "$output")"
ktap_pass "the refusal names the entry and the pid it was refused to"

[ "$interpretedstatus" -ne 0 ] || fail "a script whose interpreter lives in the scope ran"
grep -qi "not permitted" <<< "$interpreted" || fail "the refused script failed with: $interpreted"
ktap_pass "a script the allowlist names is refused with EPERM when its interpreter lives in the scope"

grep -qE "execguard: denied sh to pid [0-9]+" <<< "$output" || \
	fail "the rule did not name the interpreter: $(grep -F 'execguard:' <<< "$output")"
grep -qF "execguard: denied false" <<< "$output" && fail "the rule named the script, which the allowlist carries"
ktap_pass "the refusal names the interpreter, not the script"

[ "$after" -eq 0 ] || fail "the refused program did not run after the example was stopped (exit $after)"
ktap_pass "the rule ends with the example that made it"

waiter named "$SCOPE/true"
named=$!
waiter unnamed "$SCOPE/true"
unnamed=$!
waiter namedblocked "$SCOPE/blocked"
namedblocked=$!
WAITERS="$named $unnamed $namedblocked"
printf '%s\n' "$named" "$namedblocked" > "$SCOPE/pids" || fail "could not write the pid list"

mark_dmesg
run_script "$SCRIPT"
release named "$named"
namedstatus=$?
release unnamed "$unnamed"
unnamedstatus=$?
release namedblocked "$namedblocked"
namedblockedstatus=$?
WAITERS=""
pidoutput=$(dmesg_since)

lunatik stop "$SCRIPT" 2>/dev/null

[ "$namedstatus" -eq 0 ] || fail "a pid the list names did not run an allowed program: $(cat "$SCRATCH/named.out")"
ktap_pass "a pid the list names runs a program the allowlist names"

[ "$unnamedstatus" -ne 0 ] || fail "the exec of an allowed program by a pid the list does not name succeeded"
grep -qi "not permitted" "$SCRATCH/unnamed.out" || fail "the refused exec failed with: $(cat "$SCRATCH/unnamed.out")"
ktap_pass "the same program is refused with EPERM to a pid the list does not name"

grep -qF "execguard: denied true to pid $unnamed" <<< "$pidoutput" || \
	fail "the rule did not name the pid it refused: $(grep -F 'execguard:' <<< "$pidoutput")"
ktap_pass "the refusal names the pid the list does not carry"

[ "$namedblockedstatus" -ne 0 ] || fail "a pid the list names ran a name the allowlist does not carry"
ktap_pass "a pid the list names is still refused a name the allowlist does not carry"

errs=$(printf '%s\n' "$output" "$pidoutput" | grep -E "$KTAP_ERRORS" || true)
[ -n "$errs" ] && fail "Lua error in kernel: $errs"
ktap_pass "no Lua errors in kernel"

ktap_totals
[ $KTAP_FAIL -eq 0 ]

