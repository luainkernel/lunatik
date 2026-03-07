#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests examples/dnsblock/nf_dnsblock: verifies that domains in the blocklist
# (github.com, gitlab.com) are dropped and unlisted domains (google.com) pass.
#
# Usage: sudo bash tests/netfilter/dnsblock.sh

set -e

SCRIPT="examples/dnsblock/nf_dnsblock"
DNS_SERVER="8.8.8.8"

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; lunatik stop "$SCRIPT" 2>/dev/null; exit 1; }

# Baseline
host -W 2 github.com  "$DNS_SERVER" > /dev/null 2>&1 || fail "baseline: github.com not reachable"
host -W 2 google.com  "$DNS_SERVER" > /dev/null 2>&1 || fail "baseline: google.com not reachable"

lunatik run "$SCRIPT" false

# Blocklisted domains must be dropped
host -W 2 github.com "$DNS_SERVER" > /dev/null 2>&1 \
	&& fail "github.com should be blocked" \
	|| pass "github.com blocked"

host -W 2 gitlab.com "$DNS_SERVER" > /dev/null 2>&1 \
	&& fail "gitlab.com should be blocked" \
	|| pass "gitlab.com blocked"

# Non-blocklisted domain must pass
host -W 2 google.com "$DNS_SERVER" > /dev/null 2>&1 \
	&& pass "google.com allowed" \
	|| fail "google.com should not be blocked"

lunatik stop "$SCRIPT"

# All domains must resolve again after unload
host -W 2 github.com "$DNS_SERVER" > /dev/null 2>&1 \
	&& pass "github.com allowed after unload" \
	|| fail "github.com still blocked after unload"

