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
# Every case that spells a name discriminates, since an address declared as the
# whole struct prints 108 characters and answers to no peer. The two refusals do
# not: a second bind of one name collides whatever the declared bytes are, and the
# length bound is the binding's own argcheck either way.
#
# Usage: sudo bash tests/socket/unix/abstract.sh

SCRIPT_SERVER="tests/socket/unix/abstract"
SCRIPT_CLIENT="tests/socket/unix/abstract_client"
NAME="lunatikabstract"
LONGEST="lunatiklongest"
LONGEST_LEN=107
PEER="lunatikpeer"
MODULE="luasocket"
SLEEP=1

source "$(dirname "$(readlink -f "$0")")/../../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT_SERVER" 2>/dev/null
	lunatik stop "$SCRIPT_CLIENT" 2>/dev/null
	[ -n "${PEER_PID:-}" ] && kill "$PEER_PID" 2>/dev/null
	[ -n "${PEER_OUT:-}" ] && rm -f "$PEER_OUT"
	PEER_PID=""
}
trap cleanup EXIT
cleanup

# a leaked byte can be a space, so the name is the rest of the line past the
# seven fixed fields of /proc/net/unix, never a field of its own
procname() {
	awk -v pat="$1" '{ n = $0; if (sub(/^([^ ]+[ ]+){7}/, "", n) && index(n, pat)) print n }' /proc/net/unix
}

peer_connect() {
	python3 - "$1" <<-'PY'
	import socket, sys
	peer = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	peer.settimeout(5)
	peer.connect(("\0" + sys.argv[1]).encode())
	peer.sendall(b"ping")
	print(peer.recv(64).decode())
	peer.close()
	PY
}

peer_serve() {
	python3 - "$1" <<-'PY'
	import socket, sys
	srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
	srv.bind(("\0" + sys.argv[1]).encode())
	srv.listen(1)
	srv.settimeout(10)
	dgram = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
	dgram.bind(("\0" + sys.argv[1] + "dgram").encode())
	dgram.settimeout(10)
	conn, _ = srv.accept()
	conn.sendall(b"pong" if conn.recv(64) == b"ping" else b"?")
	conn.close()
	print("datagram:", dgram.recv(64).decode())
	PY
}

ktap_header
ktap_plan 8

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
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

command -v python3 > /dev/null 2>&1 || {
	ktap_skip "unix.abstract bind: a userspace peer connects to the bound name (no python3)"
	ktap_skip "unix.abstract connect: reaches the name a userspace peer bound (no python3)"
	ktap_skip "unix.abstract send: reaches the name a userspace peer bound (no python3)"
	check_dmesg || { ktap_totals; exit 1; }
	ktap_totals
	exit 0
}

reply=$(peer_connect "$NAME" 2>&1)
[ "$reply" = "pong" ] || fail "peer got '$reply' from the bound name, expected 'pong'"
ktap_pass "unix.abstract bind: a userspace peer connects to the bound name"

PEER_OUT=$(mktemp)
peer_serve "$PEER" > "$PEER_OUT" 2>&1 &
PEER_PID=$!
sleep $SLEEP

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

