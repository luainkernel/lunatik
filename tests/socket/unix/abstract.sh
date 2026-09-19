#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests socket.unix abstract addresses, an AF_UNIX name whose first byte is NUL:
# the address a bind registers is the name the script gave and nothing more, which
# /proc/net/unix publishes whole (a NUL as '@'), so the characters it prints are
# the assertion; the longest name UNIX_PATH_MAX admits and the first one past it;
# a second bind of one name; the empty name, which autobinds and connects to
# nothing; and a userspace peer, which reaches the bound name and is reached in
# turn only if the registered name is the one both sides spell, by connect and by
# send alike.
#
# What discriminates is a name shorter than the struct: declared whole, it prints
# 108 characters and answers to no peer. The boundary and the two refusals do not:
# a second bind of one name collides whatever the declared bytes are, and the length
# bound is the binding's own argcheck either way.
#
# Usage: sudo bash tests/socket/unix/abstract.sh

SCRIPT_SERVER="tests/socket/unix/abstract"
SCRIPT_CLIENT="tests/socket/unix/abstract_client"
NAME="lunatikabstract"
LONGEST="lunatiklongest"
LONGEST_LEN=108
PEER="lunatikpeer"
MODULE="luasocket"
SLEEP=1
DIR="$(dirname "$(readlink -f "$0")")"

source "$DIR/../../lib.sh"

PEER_BIN="$(mktemp)"
cleanup() {
	lunatik stop "$SCRIPT_SERVER" 2>/dev/null
	lunatik stop "$SCRIPT_CLIENT" 2>/dev/null
	[ -n "${PEER_PID:-}" ] && kill "$PEER_PID" 2>/dev/null
	[ -n "${PEER_OUT:-}" ] && rm -f "$PEER_OUT"
	rm -f "$PEER_BIN"
	PEER_PID=""
}
trap cleanup EXIT
cleanup

# a leaked byte can be a space, so the name is the rest of the line past the
# seven fixed fields of /proc/net/unix, never a field of its own
procname() {
	awk -v pat="$1" '{ n = $0; if (sub(/^([^ ]+[ ]+){7}/, "", n) && index(n, pat)) print n }' /proc/net/unix
}

ktap_header
ktap_plan 8

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

[ -e /proc/net/unix ] || {
	echo "# SKIP: no AF_UNIX support"
	ktap_totals
	exit 0
}

mark_dmesg
lunatik spawn "$SCRIPT_SERVER"
sleep $SLEEP
check_dmesg || { ktap_totals; exit 1; }

bound=$(procname "$NAME")
[ "$bound" = "@$NAME" ] || fail "bound name is '$bound', expected '@$NAME'"
ktap_pass "unix.abstract bind: /proc/net/unix carries the name and nothing past it"

bound=$(procname "$LONGEST")
[ ${#bound} -eq $LONGEST_LEN ] || fail "longest name printed ${#bound} characters, expected $LONGEST_LEN"
ktap_pass "unix.abstract bind: the longest name UNIX_PATH_MAX admits is declared whole"

dmesg_since | grep -q "unix abstract: duplicate bind: EADDRINUSE" || fail "a second bind of one name was not refused"
ktap_pass "unix.abstract bind: a second bind of one name is refused"

dmesg_since | grep -q "unix abstract: too long bind: .*out of bounds" || fail "a name past UNIX_PATH_MAX was not refused"
ktap_pass "unix.abstract bind: a name past UNIX_PATH_MAX is refused"

dmesg_since | grep -q "unix abstract: empty bind: bound" || fail "the empty name did not bind"
dmesg_since | grep -q "unix abstract: empty connect: EINVAL" || fail "connect to the empty name was not refused"
ktap_pass "unix.abstract: the empty name autobinds and connects to nothing"

skip_peer() {
	ktap_skip "unix.abstract bind: a userspace peer connects to the bound name ($1)"
	ktap_skip "unix.abstract connect: reaches the name a userspace peer bound ($1)"
	ktap_skip "unix.abstract send: reaches the name a userspace peer bound ($1)"
	check_dmesg || { ktap_totals; exit 1; }
	ktap_totals
	exit 0
}

command -v gcc > /dev/null 2>&1 || skip_peer "no gcc"
gcc -O2 -o "$PEER_BIN" "$DIR/abstract_peer.c" 2>/dev/null || skip_peer "peer failed to build"

reply=$("$PEER_BIN" connect "$NAME" 2>&1)
[ "$reply" = "pong" ] || fail "peer got '$reply' from the bound name, expected 'pong'"
ktap_pass "unix.abstract bind: a userspace peer connects to the bound name"

PEER_OUT=$(mktemp)
"$PEER_BIN" serve "$PEER" > "$PEER_OUT" 2>&1 &
PEER_PID=$!
for _ in $(seq 1 50); do grep -q READY "$PEER_OUT" 2>/dev/null && break; sleep 0.1; done

run_script "$SCRIPT_CLIENT"
sleep $SLEEP
wait $PEER_PID 2>/dev/null
PEER_PID=""

dmesg_since | grep -q "unix abstract: client ok" || fail "client did not reach the peer's name"
ktap_pass "unix.abstract connect: reaches the name a userspace peer bound"

grep -q "datagram: ping" "$PEER_OUT" || fail "peer did not get the datagram: $(cat "$PEER_OUT")"
ktap_pass "unix.abstract send: reaches the name a userspace peer bound"

lunatik stop "$SCRIPT_SERVER" 2>/dev/null
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

