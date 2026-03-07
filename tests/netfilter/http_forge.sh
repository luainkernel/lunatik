#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests HTTP forge hook: loads the kernel script, verifies that curl receives a
# forged 403 response from a server that normally returns 200, then unloads and
# verifies the server returns 200 again.
#
# Usage: sudo bash tests/netfilter/http_forge.sh

SCRIPT="tests/netfilter/http_forge"
PORT=8080

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; lunatik stop "$SCRIPT" 2>/dev/null; kill "$SERVER_PID" 2>/dev/null; exit 1; }

# Persistent HTTP server that always returns 200 OK
http_response() { printf "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nOK"; }
while true; do
	http_response | nc -l -p $PORT > /dev/null 2>&1
done &
SERVER_PID=$!
sleep 0.2

# Baseline: must get 200 before loading the hook
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:$PORT)
if [ "$CODE" != "200" ]; then
	fail "baseline returned $CODE, expected 200"
fi
pass "baseline 200 OK"

lunatik run "$SCRIPT" false

# Hook should forge the response to 403
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:$PORT)
if [ "$CODE" != "403" ]; then
	fail "expected 403, got $CODE"
fi
pass "response forged to 403"

lunatik stop "$SCRIPT"

# Server should return 200 again after unload
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://127.0.0.1:$PORT)
if [ "$CODE" != "200" ]; then
	fail "expected 200 after unload, got $CODE"
fi
pass "200 OK restored after unload"

kill "$SERVER_PID" 2>/dev/null

