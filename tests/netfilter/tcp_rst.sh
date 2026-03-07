#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests TCP RST hook: loads the kernel script, verifies that connecting to
# the target port gets a RST (fast rejection), then unloads and verifies
# the connection succeeds.
#
# Usage: sudo bash tests/netfilter/tcp_rst.sh

SCRIPT="tests/netfilter/tcp_rst"
PORT=7777
TIMEOUT=2

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; lunatik stop "$SCRIPT" 2>/dev/null; kill "$SERVER_PID" 2>/dev/null; exit 1; }

# Persistent server: restarts after each accepted connection
while nc -l -p $PORT > /dev/null 2>&1; do :; done &
SERVER_PID=$!
sleep 0.2

# Baseline: connection must work before the test
nc -z -w $TIMEOUT 127.0.0.1 $PORT > /dev/null 2>&1 || fail "baseline connection failed — is nc available?"
pass "baseline connection OK"
sleep 0.2  # let server loop restart after accepting

lunatik run "$SCRIPT" false

# Connection should be rejected with RST: curl exits 7 (COULDNT_CONNECT) on RST,
# 28 (OPERATION_TIMEDOUT) on drop
curl -s -o /dev/null --max-time $TIMEOUT http://127.0.0.1:$PORT
EXIT=$?
[ "$EXIT" -eq 7 ] || fail "expected RST (curl exit 7), got exit $EXIT"
pass "connection rejected with RST"

lunatik stop "$SCRIPT"

# Server still listening (SYN never reached it); connection should succeed again
if ! nc -z -w $TIMEOUT 127.0.0.1 $PORT > /dev/null 2>&1; then
	fail "connection failed after unload"
fi
pass "connection OK after unload"

kill "$SERVER_PID" 2>/dev/null
