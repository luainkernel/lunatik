#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repository pr-body-guard.cases reads: a binding and the
# example that requires it on master, with the example's README starting it with spawn, a runner, and a
# spec of autogen and an example that requires its table; a commit that changes the binding, which
# origin/fifo and the local branch local-base hold while the local branch fifo stays on master,
# fifo-test, which changes only a test on top of it, spec, which changes the spec, and run and spawn,
# which change the runner's function of that name; master is checked out, with the example's require
# and the README's verb taken out of its working tree, which a change is not read from. Beside them the
# bodies the cases post, one that names the example as examples/<name>, one that names it in backticks,
# one that carries its name only as a bare word and one that does not carry it, and the JSON gh api
# sends for each base.
#
# Usage: bash tools/checks/cases/pr-body-guard.fixture.sh <dir>

cd "$1" || exit 1
export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid
export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid
git init -q -b master . || exit 1
mkdir -p lib/lunatik examples/spyglass tests/fifo autogen
printf 'LUNATIK_NEWLIB(fifo, luafifo, &luafifo_class, NULL);\n' > lib/luafifo.c
printf 'local fifo = require("fifo")\n' > examples/spyglass/device.lua
printf 'sudo lunatik spawn examples/spyglass/device\n' > examples/spyglass/README.md
printf 'function runner.run() end\n\nfunction runner.spawn() end\n' > lib/lunatik/runner.lua
printf 'return {\n\t{ header = "uapi/linux/foo.h", prefix = "FOO_", module = "foo" },\n}\n' > autogen/specs.lua
printf 'local foo = require("linux.foo")\n' > examples/gauge.lua
printf 'run_test fifo/bounds\n' > tests/fifo/run.sh
git add lib examples tests autogen && git commit -q -m binding || exit 1
git update-ref refs/remotes/origin/master master
git branch fifo

printf '/* the buffer */\n' >> lib/luafifo.c
git commit -q -am buffer || exit 1
git update-ref refs/remotes/origin/fifo HEAD
git branch local-base
printf 'run_test fifo/fallback\n' >> tests/fifo/run.sh
git commit -q -am fallback || exit 1
git branch fifo-test
git checkout -q -b spec origin/master
sed -i 's|linux/foo.h|linux/foo_defs.h|' autogen/specs.lua
git commit -q -am spec || exit 1
for verb in run spawn; do
	git checkout -q -b $verb origin/master
	sed -i "s|runner.$verb() end|runner.$verb(script) end|" lib/lunatik/runner.lua
	git commit -q -am $verb || exit 1
done
git checkout -q master
printf 'local fifo = {}\n' > examples/spyglass/device.lua
printf 'A device.\n' > examples/spyglass/README.md

printf 'A fifo of a megabyte fails to load on a fragmented host.\n\nThe case now forces the fallback.\n' > silent.md
printf 'A fifo of a megabyte fails to load on a fragmented host.\n\nexamples/spyglass ran.\n' > named.md
printf 'A fifo of a megabyte fails to load on a fragmented host.\n\nThe spyglass of the host ran.\n' > bare.md
printf "A fifo of a megabyte fails to load on a fragmented host.\n\n\`spyglass\` ran.\n" > ticked.md
for base in master fifo; do
	jq -n --arg base "$base" --rawfile body silent.md '{head: "fifo-test", base: $base, draft: true, body: $body}' > "$base.json"
done

