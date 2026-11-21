#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Writes, in the empty directory <dir>, what merge-guard.cases reads: a gh on stub/ that answers, only
# with the token in key, that #7 is a pull request the guard merges, opened on master by the posting
# account, changing one check and the settings that wire the guards, its head carrying the
# agent-review status and passing its one check run, and that #8 is the same pull request with a
# fixup! on top of its commit.
#
# Usage: bash tools/checks/cases/merge-guard.fixture.sh <dir>

cd "$1" || exit 1
printf cases > key
mkdir -p stub
cat > stub/gh <<'STUB'
#!/bin/sh
[ "$GH_TOKEN" = cases ] || exit 1
case "$*" in
	*/pulls/[78]\ *) printf 'open\tmaster\tcases\t0123456789abcdef0123456789abcdef01234567\n' ;;
	api\ user\ *) echo cases ;;
	*/pulls/[78]/files*) printf 'tools/checks/cases.sh\n.claude/settings.json\n' ;;
	*/pulls/7/commits*) echo 'checks: name a case' ;;
	*/pulls/8/commits*) printf 'checks: name a case\nfixup! checks: name a case\n' ;;
	*/status\ *|*/check-runs*) echo success ;;
	*) exit 1 ;;
esac
STUB
chmod +x stub/gh

