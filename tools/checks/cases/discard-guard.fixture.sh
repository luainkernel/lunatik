#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repository discard-guard.cases reads: a guard edited and
# not staged, a binding changed and staged, a script and the binding's header left clean, the branch
# other and origin/master on the commit before.
#
# Usage: bash tools/checks/cases/discard-guard.fixture.sh <dir>

cd "$1" || exit 1
export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid
export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid
git init -q -b master . || exit 1
mkdir -p lib tools/checks
printf 'exit 0\n' > tools/checks/crash-guard.sh
printf 'exit 0\n' > tools/clean.sh
printf 'int luaset_new(void);\n' > lib/luaset.h
printf 'int luaset_new(void)\n{\n\treturn 0;\n}\n' > lib/luaset.c
git add lib tools && git commit -q -m base || exit 1
git branch other
git update-ref refs/remotes/origin/master HEAD
printf '# the branch'"'"'s own\n' >> tools/checks/crash-guard.sh
git add tools/checks/crash-guard.sh && git commit -q -m branch || exit 1
printf '# an edit\n' >> tools/checks/crash-guard.sh
printf '/* a change */\n' >> lib/luaset.c
git add lib/luaset.c

