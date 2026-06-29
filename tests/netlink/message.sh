#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests netlink.message: builds a message with attributes and parses it back,
# asserting the round-trip preserves the message type and attribute values;
# and the edges: malformed wire data parses to nothing (never raises), empty
# attribute sets round-trip empty, and a non-u32 number value raises.
#
# Usage: sudo bash tests/netlink/message.sh

SCRIPT="tests/netlink/message"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

ktap_header
ktap_plan 2

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg | grep -q "netlink message: round-trip ok" || fail "message round-trip failed"
ktap_pass "message: nlmsghdr/nlattr build and parse round-trip"

dmesg | grep -q "netlink message: edge cases ok" || fail "message edge cases failed"
ktap_pass "message: malformed and empty edges"

ktap_totals

