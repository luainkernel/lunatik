#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all netlink tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/netlink/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
FAILED=0

SEP=$'\n'
for t in "$DIR"/socket.sh; do
	echo "${SEP}# --- $(basename "$t") ---"
	bash "$t" || FAILED=$((FAILED+1))
done

exit $FAILED

