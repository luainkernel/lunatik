#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs all xdp tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/xdp/run.sh

DIR="$(dirname "$(readlink -f "$0")")"
FAILED=0

SEP=""
for t in "$DIR"/test_xdp.sh; do
	echo "${SEP}# --- $(basename "$t") ---"
	SEP=$'\n'
	bash "$t" || FAILED=$((FAILED+1))
done

exit $FAILED

