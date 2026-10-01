#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A thread whose body ends after its handle is gone gives luathread back.
#
# The kernel thread holds its thread object, which holds luathread, so its put
# can drop the module's last reference while the thread still runs luathread's
# code; it takes one of its own before that put and gives it back as it exits.
# module.lua is spawned, since thread.run is refused while a script loads. It
# threads a runtime whose body waits for a go and leaves a sentinel whose
# finalizer completes a completion when that runtime closes, drops the thread's
# handle, collects, and gives the go: the body returns, and the kernel thread's
# put is the thread's last, which releases it and closes its runtime. Once the
# driver is stopped, luathread's refcnt is back where it was before the driver
# ran, which a thread that keeps the reference it took fails. A thread handle
# lunatik stop drops stays in the CLI's driver, holding luathread, until that
# state collects, so the test collects there before each read.
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

settled() { [ "$(refcnt)" -eq "$before" ]; }

trap cleanup EXIT
cleanup

before=$(refcnt) || skip_all "$MODULE not loaded"

ktap_header
ktap_plan 2

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$output" ] || fail "$output"
for _ in $(seq $TRIES); do
	released && break
	sleep 0.1
done
lunatik stop "$SCRIPT" > /dev/null 2>&1
for _ in $(seq $TRIES); do
	settled && break
	sleep 0.1
done

released || fail "the runtime of a thread whose handle was collected did not close"
settled || fail "$MODULE refcnt $before -> $(refcnt) after a thread released by its own exit"
ktap_pass "a thread released as its body ends gives $MODULE back"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

