#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests opts.transform, the point of relaying in Lua at all: the hook sees every
# payload with the socket it came from, what it returns is what goes out, and
# returning nothing drops the payload from the stream.
#
# The relay's hook upper-cases what came from the A side and passes what came
# from B through, so one direction asserts the rewrite and the other asserts it
# was not applied; a hook wired to both directions, or to neither, fails one of
# the two. The drop is read as an absence, which only counts because the two
# round trips before it say the relay was carrying bytes: the peer shortens its
# own receive timeout to well past the relay's idle yield and asserts nothing
# arrived.
#
# Usage: sudo bash tests/tunnel/inspect.sh

SCRIPT="tests/tunnel/inspect"
PEER="tests/tunnel/inspect_peer"
MODULE="luasocket"

# the payloads tests/tunnel/pair.lua sends, and what the hook makes of them
ATOB="ALPHA TO BRAVO"
BTOA="bravo to alpha"
DROPPED="drop me"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$PEER" > /dev/null 2>&1
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

CASES=(
	"inspect: the far end reads what the transform rewrote"
	"inspect: the other direction is untouched, since the hook keys on its source"
	"inspect: a transform that returns nothing drops the payload"
)

ktap_header
ktap_plan ${#CASES[@]}

skip_all()
{
	echo "# SKIP: $1"
	for c in "${CASES[@]}"; do ktap_skip "$c"; done
	ktap_totals
	exit 0
}

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || skip_all "$MODULE not loaded"

mark_dmesg
out=$(lunatik spawn "$SCRIPT" 2>&1)
[ -z "$out" ] || fail "${CASES[0]}: lunatik spawn said: $out"
run_script "$PEER"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "tunnel inspect: B read $ATOB$" || fail "${CASES[0]}"
ktap_pass "${CASES[0]}"

dmesg_since | grep -q "tunnel inspect: A read $BTOA$" || fail "${CASES[1]}"
ktap_pass "${CASES[1]}"

dmesg_since | grep -q "tunnel inspect: B read nothing (EAGAIN)" ||
	fail "${CASES[2]}: the dropped payload arrived anyway"
dmesg_since | grep -q "tunnel inspect: B read $DROPPED" && fail "${CASES[2]}"
ktap_pass "${CASES[2]}"

ktap_totals

