#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests HTTPS RST hook: loads the kernel script, verifies that curl gets a
# connection reset on port 443, then unloads and verifies it connects again.
#
# Usage: sudo bash tests/netfilter/https_reject.sh

SCRIPT="tests/netfilter/https_reject"
PORT=443
TIMEOUT=2

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; lunatik stop "$SCRIPT" 2>/dev/null; kill "$SERVER_PID" 2>/dev/null; exit 1; }

# Persistent plain-TCP server on port 443 (TLS not needed — we test TCP layer)
while nc -l -p $PORT > /dev/null 2>&1; do :; done &
SERVER_PID=$!
sleep 0.2

# Baseline: TCP connect must work before the test
nc -z -w $TIMEOUT 127.0.0.1 $PORT > /dev/null 2>&1 || fail "baseline connection failed — is nc available?"
pass "baseline connection OK"
sleep 0.2

lunatik run "$SCRIPT" false

# curl should get connection reset (RST): curl exits 7 (COULDNT_CONNECT) on RST,
# 28 (OPERATION_TIMEDOUT) on drop
curl -k -s -o /dev/null --max-time $TIMEOUT https://127.0.0.1
EXIT=$?
[ "$EXIT" -eq 7 ] || fail "expected RST (curl exit 7), got exit $EXIT"
pass "curl rejected with RST"

lunatik stop "$SCRIPT"

# Server still listening; connection should succeed again
if ! nc -z -w $TIMEOUT 127.0.0.1 $PORT > /dev/null 2>&1; then
	fail "connection failed after unload"
fi
pass "connection OK after unload"

kill "$SERVER_PID" 2>/dev/null

