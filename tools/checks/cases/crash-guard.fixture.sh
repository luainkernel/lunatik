#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repository crash-guard.cases reads: a C source carrying
# a crash guard, committed and unchanged since, so an install or run over it is refused only for a
# write the same command makes. Beside it, in p, a second project as clean, with a worktree d that
# drops the guard uncommitted, the tree another session leaves while it edits.
#
# Usage: bash tools/checks/cases/crash-guard.fixture.sh <dir>

cd "$1" || exit 1
export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid
export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid
git init -q -b master . || exit 1
mkdir lib
printf 'static int luaset_new(lua_State *L)\n{\n\tluaL_argcheck(L, n > 0, 1, "empty");\n\treturn 0;\n}\n' > lib/luaset.c
git add lib/luaset.c && git commit -q -m guard
git init -q -b master p && mkdir p/lib && cp lib/luaset.c p/lib/ || exit 1
git -C p add lib/luaset.c && git -C p commit -q -m guard && git -C p worktree add -q -b d ../d || exit 1
sed -i '/luaL_argcheck/d' d/lib/luaset.c

