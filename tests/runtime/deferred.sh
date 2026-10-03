#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A runtime whose last reference drops in atomic context closes on a kernel
# worker, where its finalizers may sleep.
#
# An rcu.table entry that holds a child's only reference drops it on the
# writing task once the table's lock is dropped, and a softirq runtime's
# resumed body still holds its own lock there, with bottom halves off, as a
# hardirq one does with interrupts off. deferred_quiet.lua stores a child that
# requires byteorder as an entry's only reference and resumes a softirq
# runtime, then a hardirq one, that removes the entry. A kprobe on
# lunatik_releaseruntime says where each child closed: both on a kworker, with
# bottom halves on, and byteorder's use count is back where it was. The
# children hold nothing that runs as they close, so a build that closes them
# under the writer's lock fails that read and not the host. deferred_sleep.lua
# then drops children whose finalizer sleeps in linux.schedule before it
# reports the task it ran on, and each reports a kworker. That case runs only
# after the first passed, and the test skips unless the loaded core carries
# lunatik_deferirq, since a build that closes them under the writer's lock
# sleeps in atomic context.
#
# Usage: sudo bash tests/runtime/deferred.sh

QUIET="tests/runtime/deferred_quiet"
SLEEP="tests/runtime/deferred_sleep"
MODULE="luabyteorder"
FIX="lunatik_deferirq"
RELEASES="lunatik_deferred/lunatik_releaseruntime"
CHILDREN=2 # one per writer, a softirq and a hardirq runtime
TRIES=50

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$QUIET" > /dev/null 2>&1
	lunatik stop "$SLEEP" > /dev/null 2>&1
	kprobe_remove "$RELEASES"
}

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

refcnt() { cat "/sys/module/$MODULE/refcnt" 2>/dev/null; }
# the hits a kworker took, each line led by its task, then its CPU and its flags
deferred() { awk -v event="${RELEASES#*/}:" '$1 ~ /^kworker\// && $5 == event' "$TRACING/instances/${RELEASES%%/*}/trace"; }
slept() { dmesg_since | grep -c "deferred test: slept on kworker/"; }

closed() { [ "$(deferred | wc -l)" -ge "$CHILDREN" ]; }
released() { [ "$(refcnt)" -eq "$before" ]; }
reported() { [ "$(slept)" -ge "$CHILDREN" ]; }

trap cleanup EXIT
cleanup

grep -qw "$FIX" /proc/kallsyms || skip_all "the loaded core does not carry $FIX: a finalizer would sleep under the writer's lock"
before=$(refcnt) || skip_all "$MODULE not loaded"
kprobe_place "$RELEASES" lunatik_releaseruntime || skip_all "couldn't place a kprobe on lunatik_releaseruntime"

ktap_header
ktap_plan 4

mark_dmesg
run_script "$QUIET"
lunatik stop "$QUIET" > /dev/null 2>&1

awaited closed
hits=$(deferred | wc -l)
[ "$hits" -eq "$CHILDREN" ] || fail "$hits of the $CHILDREN children closed on a kworker, the rest under the writer's lock"
off=$(deferred | awk '{ print substr($3, 1, 1) }' | grep -c '^[bD]$')
[ "$off" -eq 0 ] || fail "$off of the children closed on a kworker with bottom halves off"
ktap_pass "a child an atomic writer drops closes on a kworker, with bottom halves on"

awaited released
released || fail "$MODULE refcnt $before -> $(refcnt) after the deferred closes: a child left open"
ktap_pass "a child closed on a kworker releases what its state held"

run_script "$SLEEP"
lunatik stop "$SLEEP" > /dev/null 2>&1

awaited reported
[ "$(slept)" -eq "$CHILDREN" ] || {
	comment "$(dmesg_since | grep -F "deferred test:")"
	fail "$(slept) of the $CHILDREN finalizers slept on a kworker"
}
ktap_pass "a finalizer of a child an atomic writer drops sleeps on a kworker"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

