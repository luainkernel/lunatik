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
# one that names it beside a command run under GH_REPO, one that carries its name only as a bare word
# and one that does not carry it, the last again under repos/drafts/, a path that reads as an
# endpoint's, and the JSON gh api sends for each base; under sub/, read only after a cd into it, the
# body that names the example and a GraphQL mutation that carries no text. For an issue edit, a gh on
# stub/ that answers the body GitHub has for luainkernel/lunatik#5 and for luainkernel/lua#5, each
# carrying a line untraced.sh fails, the bodies that repeat each, one that adds a line, and the held
# lists review-post-guard writes, through that gh, for the session none: under ours/ for a comment on
# this repository's #5, under placeholder/ for one on {owner}/{repo}'s #5, and under other/ for one on
# luainkernel/lua#5; a gh on keyed/ answers as stub/'s only with the token in key.
#
# Usage: bash tools/checks/cases/pr-body-guard.fixture.sh <dir>

guard=$(cd "$(dirname "$0")/.." && pwd)/review-post-guard.sh
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
printf 'A fifo of a megabyte fails to load on a fragmented host.\n\nexamples/spyglass ran, GH_REPO=luainkernel/lunatik lunatik spawn.\n' > repo.md
mkdir -p repos/drafts
cp silent.md repos/drafts/silent.md
for base in master fifo; do
	jq -n --arg base "$base" --rawfile body silent.md '{head: "fifo-test", base: $base, draft: true, body: $body}' > "$base.json"
done
printf 'A fifo.\n\nThe fifo test is a flake.\n' > fifo.md
printf 'A table.\n\nThe table test is a flake.\n' > table.md
printf 'A fifo.\n\nThe buffer holds a page.\n' > new.md
mkdir -p stub
cat > stub/gh <<STUB
#!/bin/sh
case "\$*" in
	*"/lunatik/issues/5 --jq .body"|*"{repo}/issues/5 --jq .body") cat "$PWD/fifo.md" ;;
	*"/lua/issues/5 --jq .body") cat "$PWD/table.md" ;;
	*) exit 1 ;;
esac
STUB
chmod +x stub/gh
printf '> [!NOTE]\n> This comment was written by an LLM, not a human.\n\nThe callback returns the queue.\n' > note.md
for held in "ours gh issue comment 5 --body-file note.md" \
	"placeholder gh api -X POST repos/{owner}/{repo}/issues/5/comments -F body=@note.md" \
	"other gh api -X POST repos/luainkernel/lua/issues/5/comments -F body=@note.md"; do
	jq -n --arg command "${held#* }" --arg cwd "$PWD" '{tool_name: "Bash", tool_input: {command: $command}, cwd: $cwd}' |
		PATH=$PWD/stub:$PATH LUNATIK_GUARD_DIR=${held%% *} bash "$guard"
done
mkdir -p sub
cp named.md sub/body.md
printf 'mutation { markPullRequestReadyForReview(input: {pullRequestId: "PR_1"}) { clientMutationId } }\n' > sub/ready.graphql

printf cases > key
mkdir -p keyed
cat > keyed/gh <<STUB
#!/bin/sh
[ "\$GH_TOKEN" = cases ] && exec "$PWD/stub/gh" "\$@"
exit 1
STUB
chmod +x keyed/gh

