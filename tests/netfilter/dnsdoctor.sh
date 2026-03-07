#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Smoke-tests examples/dnsdoctor/nf_dnsdoctor: verifies the hook registers
# and unregisters cleanly. Full integration (DNS response rewriting for
# lunatik.com → 10.1.2.3) requires a DNS server at 10.1.1.2 and is out of
# scope for this test.
#
# Usage: sudo bash tests/netfilter/dnsdoctor.sh

set -e

SCRIPT="examples/dnsdoctor/nf_dnsdoctor"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; lunatik stop "$SCRIPT" 2>/dev/null; exit 1; }

lunatik run  "$SCRIPT" false && pass "hook registered" || fail "failed to register hook"
lunatik stop "$SCRIPT" && pass "hook unregistered" || fail "failed to unregister hook"

