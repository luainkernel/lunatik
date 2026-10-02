#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# thread.run keeps the thread for the runtime that calls it: dropping the handle
# stops nothing, a stop called there lets the handle go, and the end of that
# runtime stops the thread, whoever else holds it.
#
# keep.lua is spawned, since thread.run is refused while a script loads. It
# threads a runtime whose body returns at once into a weak table and collects:
# the thread is still there, since the driver's runtime keeps it, and once the
# driver stops it a second collect takes it. A second handle of a thread the
# driver started, read back from an rcu.table, is collected and stops nothing:
# the body, which waits three seconds at most for a stop and completes a
# completion when one came, has seen none by the time the collect returns.
# Then a creator runtime threads a runtime with that body and hands the thread
# to the driver: the driver stops the creator, and the body has seen the stop
# by the time that stop returns, though the driver still holds the thread; its
# own stop of it afterwards returns true.
# Last, a thread the driver stops itself, from a runtime other than the one
# that started it, stops, and the end of its creator afterwards finds it
# stopped. A build that does not keep the thread fails the first case at the
# first collect, one that stops it when any of its handles in that runtime is
# collected fails the second, and one whose end does not stop it fails the
# third, before the driver's stop ends the body; no body outlives its case.
#
# Usage: sudo bash tests/thread/keep.sh

SCRIPT="tests/thread/keep"
TRIES=100

source "$(dirname "$(readlink -f "$0")")/../lib.sh"
source "$(dirname "$(readlink -f "$0")")/driver.sh"

cleanup() { lunatik stop "$SCRIPT" > /dev/null 2>&1; }
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 5

mark_dmesg
output=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$output" ] || fail "$output"
awaited reported "foreign"
lunatik stop "$SCRIPT" > /dev/null 2>&1

verdict "kept" "a dropped thread stays kept by the runtime that started it until a stop there"
verdict "cloned" "a second handle of a thread, collected in the runtime that started it, stops nothing"
verdict "ended" "the end of the runtime that started a thread stops it, though another runtime holds it"
verdict "foreign" "a thread stopped from another runtime is found stopped by the end of its creator"

check_dmesg && ktap_pass "no Lua errors in kernel"

ktap_totals

