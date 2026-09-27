#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Drives the spawned examples/cpuexporter daemon over its own socket: a request
# is answered with the OpenMetrics text the example exists to serve, and a peer
# that connects and says nothing leaves the daemon to stop on its own terms
# rather than have the stop tear its receive out from under it.
#
# The second case reads the absence of "error handling client", which is what an
# unbounded receive leaves behind: kthread_stop() sets TIF_NOTIFY_SIGNAL since
# a7c01fa93aeb (v6.1), so the receive raises ERESTARTSYS into the daemon's pcall
# instead of returning a request. Below v6.1 nothing sets that flag and the same
# regression parks the daemon for good, with the stop waiting on it inside
# write(2) on /dev/lunatik, so the case skips there rather than wedge the host.
#
# The peers are userspace ones, since a session has to stay open across the stop
# and a lunatik client shuts its socket down when its runtime goes; the suite
# skips without python3.
#
# Usage: sudo bash tests/examples/cpuexporter.sh

EXAMPLE="examples/cpuexporter"
SOCK="/tmp/cpuexporter.sock"
MODULES="luasocket luacpu"
STOPPABLE="6.1"
SLEEP=1
PEER=""

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	[ -n "$PEER" ] && kill "$PEER" 2>/dev/null
	PEER=""
	lunatik stop "$EXAMPLE" > /dev/null 2>&1
	rm -f "$SOCK"
}
trap cleanup EXIT
cleanup

request() {
	python3 -c '
import socket, sys

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
client.settimeout(5)
client.connect(sys.argv[1])
client.sendall(b"GET /metrics HTTP/1.0\r\n\r\n")
reply = b""
while True:
	chunk = client.recv(65536)
	if not chunk:
		break
	reply += chunk
client.close()
sys.stdout.write(reply.decode())
' "$SOCK"
}

ktap_header
ktap_plan 2

for module in $MODULES; do
	cat /sys/module/$module/refcnt > /dev/null 2>&1 || {
		echo "# SKIP: $module not loaded"
		ktap_totals
		exit 0
	}
done

command -v python3 > /dev/null 2>&1 || {
	echo "# SKIP: python3 not found"
	ktap_totals
	exit 0
}

mark_dmesg
spawned=$(lunatik spawn "$EXAMPLE" 2>&1)
[ -z "$spawned" ] || { comment "$spawned"; fail "$EXAMPLE did not spawn"; }
sleep $SLEEP

metrics=$(request)
case "$metrics" in
	*"# TYPE cpu_usage_"*) ;;
	*) comment "$metrics"; fail "the request was not answered with metrics" ;;
esac
ktap_pass "cpuexporter: a request is answered with the metrics"

if kernel_atleast "$STOPPABLE"; then
	hold_session "$SOCK"
	PEER=$!
	sleep $SLEEP
	lunatik stop "$EXAMPLE" > /dev/null 2>&1
	sleep $SLEEP
	torn=$(dmesg_since | grep "cpud \[daemon\]: error handling client" || true)
	ended=$(dmesg_since | grep "cpud \[daemon\]: stopped" || true)
	kill "$PEER" 2>/dev/null; PEER=""
	[ -z "$torn" ] && [ -n "$ended" ] || { comment "$torn"; fail "the stop tore the daemon out of its receive"; }
	ktap_pass "cpuexporter: a peer that says nothing does not make the stop an error"
else
	ktap_skip "cpuexporter: a peer that says nothing does not make the stop an error"
fi

cleanup
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

