#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Regression test for the checker matrix: a method of every class a process
# runtime can construct (data, fifo, completion, set, crypto.shash,
# crypto.skcipher, crypto.aead, crypto.rng, task, thread, lunatik.runtime,
# fsnotify.watch),
# called through the class's metatable, refuses an object of another class
# naming both classes, which proves the metatables carry __name,
# refuses nil and a userdata of another library (io's) as no object at all;
# rcu.foreach refuses nil the same way; and a method on a closed runtime or fifo,
# whose private is gone, is refused instead of dereferencing NULL. The thread
# object is a spawned body's, since thread.run is refused from a script body.
#
# The close case, foreign_checker_close, closes a thread, a device and a
# runtime through fifo's close, lunatik_closeobject, which refuses each as an
# object of another class, and a thread, a device and a fifo through the
# runtime's stop, which refuses each naming both classes; each object then
# answers its own methods, the thread's stop among them, run by the CLI. It
# also closes a crypto.shash through its __close, the entry the refusal reads,
# and reads the object closed. A build without the refusals does not fail this
# case, it closes the thread and the device under methods that read their
# private without a check, and the CLI's stop of the thread dereferences NULL,
# so the case skips unless the loaded core is the installed one and that file
# carries the refusal: the check is inline, so no symbol of its own is in
# /proc/kallsyms, and the message is what the installed lunatik.ko has.
#
# Usage: sudo bash tests/runtime/foreign_checker.sh

SCRIPT="tests/runtime/foreign_checker"
CLOSE="tests/runtime/foreign_checker_close"
BODY="tests/runtime/my_body"
MODULE="lunatik"
REFUSAL="object of another class"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$CLOSE" > /dev/null 2>&1
	lunatik stop "$BODY" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 2

mark_dmesg
output=$(lunatik spawn "$BODY" 2>&1)
[ -n "$output" ] && fail "spawn failed: $output"
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }
lunatik stop "$SCRIPT" > /dev/null 2>&1
ktap_pass "every checker refuses another class, nil, a foreign userdata and a closed object"

if [ "$(cat /sys/module/$MODULE/srcversion 2> /dev/null)" = "$(modinfo -F srcversion $MODULE 2> /dev/null)" ] &&
	grep -qaF "$REFUSAL" "$(modinfo -n $MODULE 2> /dev/null)"; then
	run_script "$CLOSE"
	cli stop "$BODY"
	lunatik stop "$CLOSE" > /dev/null 2>&1
	[ "$status" = 0 ] || fail "the thread's stop failed after the refused closes: $err"
	check_dmesg || { ktap_totals; exit 1; }
	ktap_pass "a close of another class refuses a thread, a device and a runtime, which keep their own stop"
else
	ktap_skip "the installed $MODULE is not loaded or does not carry the refusal: a foreign close would dereference NULL"
fi

ktap_totals

