#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, what fixup-guard.cases reads: the JSON gh api sends for a create
# of folded on master and of clean on master, and under sub/, read only after a cd into it, the one of
# folded; beside them a gh on stub/ that answers GitHub's compare of folded with master with a fixup!
# among its subjects and the compare of clean with plain subjects, in luainkernel/lunatik or the
# checkout's repository alone.
#
# Usage: bash tools/checks/cases/fixup-guard.fixture.sh <dir>

cd "$1" || exit 1
mkdir -p stub sub
jq -n '{head: "folded", base: "master", body: "A fifo."}' > folded.json
jq -n '{head: "clean", base: "master", body: "A fifo."}' > clean.json
cp folded.json sub/f.json
cat > stub/gh <<'STUB'
#!/bin/sh
case "$*" in
	*/luainkernel/lunatik/compare/master...folded\ *|*/{owner}/{repo}/compare/master...folded\ *) printf '%s\n' 'fifo: add a fifo' 'fixup! fifo: add a fifo' ;;
	*/luainkernel/lunatik/compare/master...clean\ *|*/{owner}/{repo}/compare/master...clean\ *) printf '%s\n' 'fifo: add a fifo' 'fifo: drain it' ;;
	*) exit 1 ;;
esac
STUB
chmod +x stub/gh

