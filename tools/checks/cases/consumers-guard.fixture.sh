#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repository consumers-guard.cases reads: a binding on master,
# bump, which changes it and which origin/bump holds too, stacked, which changes only a test on top of
# it, origin/lag, a base fetched before GitHub moved it to bump, and docs, which changes only the README
# and is the branch checked out; beside them consumer/, a script out of the tree that requires the
# binding, the JSON gh api sends for a create of bump, and a gh on stub/ that answers for GitHub's
# pulls/9, bump on master, pulls/8, stacked on bump, pulls/6, a head this checkout lacks, and the tip
# of lag.
#
# Usage: bash tools/checks/cases/consumers-guard.fixture.sh <dir>

cd "$1" || exit 1
export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid
export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid
git init -q -b master . || exit 1
mkdir -p lib tests/fifo consumer stub
printf 'LUNATIK_NEWLIB(fifo, luafifo, &luafifo_class, NULL);\n' > lib/luafifo.c
printf 'run_test fifo/bounds\n' > tests/fifo/run.sh
printf 'A fifo.\n' > README.md
git add lib tests README.md && git commit -q -m binding || exit 1
git update-ref refs/remotes/origin/master master

git checkout -q -b bump
printf '/* the buffer */\n' >> lib/luafifo.c
git commit -q -am buffer || exit 1
git update-ref refs/remotes/origin/bump HEAD
git checkout -q -b stacked
printf 'run_test fifo/fallback\n' >> tests/fifo/run.sh
git commit -q -am fallback || exit 1
git update-ref refs/remotes/origin/lag master
git checkout -q -b docs master
printf 'A fifo of a page.\n' > README.md
git commit -q -am docs || exit 1

printf 'local fifo = require("fifo")\n' > consumer/app.lua
jq -n '{head: "bump", base: "master", body: "A fifo."}' > bump.json
cat > stub/gh <<STUB
#!/bin/sh
case "\$*" in
	*pulls/9\ *) echo "$(git rev-parse bump) master" ;;
	*pulls/8\ *) echo "$(git rev-parse stacked) bump" ;;
	*pulls/6\ *) echo "0123456789abcdef0123456789abcdef01234567 master" ;;
	*branches/lag\ *) echo "$(git rev-parse bump)" ;;
	*) exit 1 ;;
esac
STUB
chmod +x stub/gh

