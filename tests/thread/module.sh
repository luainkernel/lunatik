#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A thread whose stop the end of the runtime that started it hands to a kernel
# worker gives luathread back, and that end, run from the thread's own body,
# stops the thread through the worker.
#
# A work holds its thread object, which holds luathread, so its last put can
# drop the module's last reference while the work still runs luathread's code;
# the module's exit flushes the core's queue before the code goes. module.lua is
# spawned, since thread.run is refused while a script loads. A creator runtime
# it makes threads a runtime whose body leaves a sentinel whose finalizer
# completes a completion when that runtime closes, waits for a go, stops the
# creator and then waits three seconds at most for a stop of its own, completing
# a second completion when one came; the driver drops the thread and that
# runtime's handle, collects, and gives the go. The creator's end stops the
# threads it keeps, and cannot wait for this one on its body, which runs under
# its runtime's lock: it hands the stop to a kernel worker, which stops the
# thread once the body sees the stop and returns, and its put of the thread's
# runtime closes it. Once the driver is stopped, luathread's refcnt is back
# where it was before the driver ran, which a work that keeps its reference
# fails. A thread handle lunatik stop drops stays in the CLI's driver, holding
# luathread, until that state collects, so the test collects there before each
# read. A build whose end leaves that thread to its body closes its runtime when
# the body's wait runs out, and fails the stop.
#
# Usage: sudo bash tests/thread/module.sh

SCRIPT="tests/thread/module"
MODULE="luathread"
PREFIX="thread module test: "
TRIES=50

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }

skip_all() { ktap_header; ktap_plan 1; ktap_skip "$1"; ktap_totals; exit 0; }

refcnt() { lunatik -e "collectgarbage()" > /dev/null; cat "/sys/module/$MODULE/refcnt" 2>/dev/null; }

released() { dmesg_since | grep -qF "${PREFIX}released"; }

stopped() { dmesg_since | grep -qF "${PREFIX}stopped"; }

settled() { [ "$(refcnt)" -eq "$before" ]; }

trap cleanup EXIT
cleanup

before=$(refcnt) || skip_all "$MODULE not loaded"

ktap_header
ktap_plan 3

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$output" ] || fail "$output"
for _ in $(seq $TRIES); do
	stopped && break
	sleep 0.1
done
lunatik stop "$SCRIPT" > /dev/null 2>&1
for _ in $(seq $TRIES); do
	settled && break
	sleep 0.1
done

released || fail "the runtime of a thread whose handle was collected did not close"
settled || fail "$MODULE refcnt $before -> $(refcnt) after a thread released by its worker"
ktap_pass "a thread whose stop a worker made gives $MODULE back"

stopped || fail "the end of the runtime that started a thread, run from that thread's body, did not stop it"
ktap_pass "the end of the runtime that started a thread, run from its body, stops it through a worker"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

