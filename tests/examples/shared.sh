#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Drives the spawned examples/shared daemon over its own port with a kernel-side
# client: a GET of a key that was never assigned, and a GET of a key a SET
# removed, must each answer with an empty line rather than take the thread body
# down and leave the port bound with nobody in accept(); and a GET of a key that
# was set must answer with the value and nothing else, a rewrite to a shorter
# value included, which only a byte-exact assertion tells from the whole slot.
#
# The peer that resets its session is a userspace one: luasocket's release shuts
# the socket down before releasing it, so a lunatik client always says goodbye
# with a FIN, which the daemon reads as a clean end of session. A close with the
# reply still unread is what the daemon raises on, and only a later connection
# getting an answer tells that it survived.
#
# Usage: sudo bash tests/examples/shared.sh

SCRIPT="tests/examples/shared_client"
EXAMPLE="examples/shared"
MODULE="luasocket"
SLEEP=1
BINDS=15
BIND_WAIT=5

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	lunatik stop "$EXAMPLE" > /dev/null 2>&1
}
trap cleanup EXIT
cleanup

# closing with the reply unread zaps the connection with a reset, the
# data_was_unread arm of tcp_close, instead of the FIN a drained socket sends
reset_session() {
	python3 - <<'PY'
import socket, sys

def connect():
	return socket.create_connection(("127.0.0.1", 90), timeout=2)

client = connect()
client.sendall(b"rst=x\n")
client.close()

client = connect()
client.sendall(b"rst\n")
client.recv(4096, socket.MSG_PEEK)
client.close()

client = connect()
client.sendall(b"rst\n")
reply = client.recv(4096)
client.close()

sys.exit(0 if reply else 1)
PY
}

ktap_header
ktap_plan 5

cat /sys/module/$MODULE/refcnt > /dev/null 2>&1 || {
	echo "# SKIP: $MODULE not loaded"
	ktap_totals
	exit 0
}

mark_dmesg
# a run the daemon did not survive leaves its session for the runtime teardown to
# close, and that close sends the first FIN, so 127.0.0.1:90 sits in TIME_WAIT
# until TCP_TIMEWAIT_LEN; no bind gets past it without SO_REUSEADDR
for _ in $(seq 1 $BINDS); do
	spawned=$(lunatik spawn "$EXAMPLE" 2>&1)
	case "$spawned" in *EADDRINUSE*) sleep $BIND_WAIT ;; *) break ;; esac
done
[ -z "$spawned" ] || { comment "$spawned"; fail "$EXAMPLE did not spawn"; }
sleep $SLEEP

run_script "$SCRIPT"
lunatik stop "$SCRIPT" > /dev/null 2>&1

dmesg_since | grep -q "shared example: unset ok" || fail "a GET of a key never assigned did not answer"
ktap_pass "shared: a GET of a key that was never assigned answers with an empty line"

dmesg_since | grep -q "shared example: removed ok" || fail "a GET of a key a SET removed did not answer"
ktap_pass "shared: a GET of a key a SET removed answers with an empty line"

if command -v python3 > /dev/null 2>&1; then
	reset=$(reset_session 2>&1) || { comment "$reset"; fail "no answer after a peer reset its session"; }
	ktap_pass "shared: a peer that resets its session does not end the daemon"
else
	ktap_skip "shared: a peer that resets its session does not end the daemon"
fi

dmesg_since | grep -q "shared example: value ok" || fail "a GET did not answer with the value alone"
ktap_pass "shared: a GET answers with the value and nothing else"

dmesg_since | grep -q "shared example: rewrite ok" || fail "a rewritten key did not answer with the new value alone"
ktap_pass "shared: a SET over a longer value answers with the shorter one alone"

cleanup
check_dmesg || { ktap_totals; exit 1; }

ktap_totals

