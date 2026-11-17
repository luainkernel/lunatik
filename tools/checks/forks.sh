#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Names each fork a submodule of the tree follows whose lunatik branch is not at the tip of its kernel
# branch, the newest of its branches named <release>-kernel, which lunatik follows (AGENTS.md, Layout):
# a merge into the kernel branch moves lunatik in the same pass (the merged skill). Reads each fork
# .gitmodules names with git ls-remote; exits 1 when one lags or cannot be read.
#
# Usage: bash tools/checks/forks.sh

status=0
while read -r _ url; do
	heads=$(git ls-remote --heads "$url") || { status=1; continue; }
	lunatik=$(awk '$2 == "refs/heads/lunatik" { print $1 }' <<< "$heads")
	read -r tip kernel < <(awk '$2 ~ /-kernel$/' <<< "$heads" | sort -V -k 2 | tail -n 1)
	[ "$lunatik" != "$tip" ] || continue
	echo "forks: $url: lunatik is at ${lunatik:0:12}, not at ${kernel#refs/heads/}'s ${tip:0:12}; push that tip to lunatik (the merged skill)"
	status=1
done < <(git config -f "$(dirname "$0")/../../.gitmodules" --get-regexp '^submodule\..*\.url$')
exit $status

