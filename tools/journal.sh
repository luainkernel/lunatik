#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Prints every unit's journal lines, not only the kernel's, around the last
# kernel line that matches a pattern. The window a test's own prints sit in is
# where a host process acting on what the test created shows up: NetworkManager
# and wpa_supplicant taking the AP interface tests/netlink/nl80211_station had
# just brought up (#1010) were there, and nowhere in the KTAP output. The suite
# clears the ring buffer at every test, so dmesg is not the record; the journal is.
# Needs the journal's read permission: the adm group grants it, sudo otherwise.
#
# Usage: bash tools/journal.sh <pattern> [seconds before and after, default 3]

pattern=$1
span=${2:-3}

[ -n "$pattern" ] || { echo "usage: $0 <pattern> [seconds]"; exit 1; }

last=$(journalctl -q -k -o short-iso --grep="$pattern" 2>/dev/null | tail -1 | cut -d' ' -f1)
[ -n "$last" ] || { echo "no kernel line matches $pattern"; exit 1; }
at=$(date -d "$last" +%s)

journalctl -q -o short-iso --since "@$((at - span))" --until "@$((at + span))"

