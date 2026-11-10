#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, what stacked-guard.cases reads: the JSON gh api sends for a create
# of stacked on bump, the same asking for a draft, the same on master, and a move onto bump; under sub/,
# read only after a cd into it, the create on bump twice, once named as the one on master; beside them
# a gh on stub/ that answers GitHub's pulls/9 is not a draft and pulls/8 is one, in luainkernel/lunatik or
# the checkout's repository alone.
#
# Usage: bash tools/checks/cases/stacked-guard.fixture.sh <dir>

cd "$1" || exit 1
mkdir -p stub sub
jq -n '{head: "stacked", base: "bump", body: "A fifo."}' > stacked.json
jq -n '{head: "stacked", base: "bump", draft: true, body: "A fifo."}' > draft.json
jq -n '{head: "stacked", base: "master", body: "A fifo."}' > master.json
jq -n '{base: "bump"}' > move.json
cp stacked.json sub/s.json
cp stacked.json sub/master.json
cat > stub/gh <<'STUB'
#!/bin/sh
case "$*" in
	*pulls/9\ *) echo false ;;
	*/luainkernel/lunatik/pulls/8\ *|*/{owner}/{repo}/pulls/8\ *) echo true ;;
	*) exit 1 ;;
esac
STUB
chmod +x stub/gh

