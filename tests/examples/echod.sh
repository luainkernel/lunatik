#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Drives the spawned examples/echod daemon over its own port: what a client
# sends comes back byte for byte, a second client is served while the first one
# holds its session and sends nothing, and the worker of a session whose peer
# went silent ends when the daemon does.
#
# That last case is the one no kernel can rescue. The daemon discards the thread
# object it makes per connection, so nobody ever calls kthread_stop() on a
# worker: a worker parked in a receive is parked for good, and it keeps
# executing luathread.ko text that the next reload frees underneath it. Only the
# worker's own poll of the daemon's control byte ends it, and the "stopped" line
# is what says the poll happened.
#
# The peers are userspace ones, since a session has to stay open across the stop
# and a lunatik client shuts its socket down when its runtime goes; the suite
# skips without python3.
#
# Usage: sudo bash tests/examples/echod.sh

EXAMPLE="examples/echod/daemon"
MODULE="luasocket"
PORT=1337
SLEEP=1
BINDS=15
BIND_WAIT=5
PEER=""

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	[ -n "$PEER" ] && kill "$PEER" 2>/dev/null
	PEER=""
	lunatik stop "$EXAMPLE" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

exchange() {
	python3 -c '
import socket, sys

client = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5)
client.sendall(sys.argv[2].encode())
sys.stdout.write(client.recv(4096).decode())
client.close()
' "$PORT" "$1"
}

hold() {
	hold_session "$PORT"
	PEER=$!
	sleep $SLEEP
}

# the sleep lets the freed worker run its last poll, so its own "stopped" line
# is not still in flight when the next case counts them
release() {
	kill "$PEER" 2>/dev/null
	PEER=""
	sleep $SLEEP
}

stopped() { dmesg_since | grep -c "echod \\[worker #.*\\]: stopped" || true; }

ktap_header
ktap_plan 3

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

command -v python3 > /dev/null 2>&1 || {
	echo "# SKIP: python3 not found"
	ktap_totals
	exit 0
}

mark_dmesg
# a session the kernel side closes first leaves 127.0.0.1:1337 in TIME_WAIT
# until TCP_TIMEWAIT_LEN, and no bind gets past it without SO_REUSEADDR
for _ in $(seq 1 $BINDS); do
	spawned=$(lunatik spawn "$EXAMPLE" 2>&1)
	case "$spawned" in *EADDRINUSE*) sleep $BIND_WAIT ;; *) break ;; esac
done
[ -z "$spawned" ] || { comment "$spawned"; fail "$EXAMPLE did not spawn"; }
sleep $SLEEP

reply=$(exchange "hello kernel!")
[ "$reply" = "hello kernel!" ] || { comment "got: $reply"; fail "the echo did not come back"; }
ktap_pass "echod: what a client sends comes back byte for byte"

hold
reply=$(exchange "second")
release
[ "$reply" = "second" ] || { comment "got: $reply"; fail "a silent peer kept the next client waiting"; }
ktap_pass "echod: a second client is served while the first one sends nothing"

before=$(stopped)
hold
lunatik stop "$EXAMPLE" > /dev/null 2>&1
sleep $SLEEP
after=$(stopped)
release
[ "$after" -gt "$before" ] || fail "the worker of a silent peer outlived the daemon"
ktap_pass "echod: the worker of a session whose peer went silent ends with the daemon"

cleanup
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

