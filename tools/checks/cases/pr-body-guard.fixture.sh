#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repository pr-body-guard.cases reads: a binding and the
# example that requires it on master, a commit that changes the binding, which origin/fifo and the local
# branch local-base hold while the local branch fifo stays on master, and fifo-test, which changes only a
# test on top of it; beside them the bodies the cases post, one that names the example and one that does
# not, and the JSON gh api sends for each base.
#
# Usage: bash tools/checks/cases/pr-body-guard.fixture.sh <dir>

cd "$1" || exit 1
export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid
export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid
git init -q -b master . || exit 1
mkdir -p lib examples/spyglass tests/fifo
printf 'LUNATIK_NEWLIB(fifo, luafifo, &luafifo_class, NULL);\n' > lib/luafifo.c
printf 'local fifo = require("fifo")\n' > examples/spyglass/device.lua
printf 'run_test fifo/bounds\n' > tests/fifo/run.sh
git add lib examples tests && git commit -q -m binding || exit 1
git update-ref refs/remotes/origin/master master
git branch fifo

printf '/* the buffer */\n' >> lib/luafifo.c
git commit -q -am buffer || exit 1
git update-ref refs/remotes/origin/fifo HEAD
git branch local-base
printf 'run_test fifo/fallback\n' >> tests/fifo/run.sh
git commit -q -am fallback || exit 1
git branch fifo-test
git checkout -q master

printf 'A fifo of a megabyte fails to load on a fragmented host.\n\nThe case now forces the fallback.\n' > silent.md
printf 'A fifo of a megabyte fails to load on a fragmented host.\n\nexamples/spyglass ran.\n' > named.md
for base in master fifo; do
	jq -n --arg base "$base" --rawfile body silent.md '{head: "fifo-test", base: $base, draft: true, body: $body}' > "$base.json"
done

