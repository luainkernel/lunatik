#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repository consumers-guard.cases reads: on master a binding,
# a second one and a library that requires it, a third one and a binding that builds its objects, and a
# spec of autogen; bump, which changes the first binding and which origin/bump holds too, stacked, which
# changes only a test on top of it, origin/lag, a base fetched before GitHub moved it to bump, ring,
# which changes the second binding, reel, which changes the third, coil, which adds a fourth, spec, which
# changes the spec, and docs, which changes only the README and is the branch checked out, with the
# library's require and the call that builds the third binding's objects taken out of its working tree;
# beside them consumer/, scripts out of the tree that require the first binding, the library, the binding
# that builds the third's objects, the fourth binding and the spec's table, the JSON gh api sends for a
# create of bump, under sub/, read only after a cd into it, the one for a create of docs, and a gh on
# stub/ that answers for GitHub's pulls/9, bump on master, pulls/8, stacked on bump, pulls/6, a head this
# checkout lacks, and the tip of lag, and one on keyed/ that answers as it only with the token in key.
#
# Usage: bash tools/checks/cases/consumers-guard.fixture.sh <dir>

cd "$1" || exit 1
export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid
export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid
git init -q -b master . || exit 1
mkdir -p lib tests/fifo autogen consumer stub
printf 'LUNATIK_NEWLIB(fifo, luafifo, &luafifo_class, NULL);\n' > lib/luafifo.c
printf 'LUNATIK_NEWLIB(ring, luaring, &luaring_class, NULL);\n' > lib/luaring.c
printf 'local ring = require("ring")\n' > lib/spool.lua
printf 'LUNATIK_NEWLIB(reel, luareel, &luareel_class, NULL);\n' > lib/luareel.c
printf 'LUNATIK_NEWLIB(spin, luaspin, &luaspin_class, NULL);\nluareel_new(L);\n' > lib/luaspin.c
printf 'run_test fifo/bounds\n' > tests/fifo/run.sh
printf 'return {\n\t{ header = "uapi/linux/foo.h", prefix = "FOO_", module = "foo" },\n}\n' > autogen/specs.lua
printf 'A fifo.\n' > README.md
git add lib tests autogen README.md && git commit -q -m binding || exit 1
git update-ref refs/remotes/origin/master master

git checkout -q -b bump
printf '/* the buffer */\n' >> lib/luafifo.c
git commit -q -am buffer || exit 1
git update-ref refs/remotes/origin/bump HEAD
git checkout -q -b stacked
printf 'run_test fifo/fallback\n' >> tests/fifo/run.sh
git commit -q -am fallback || exit 1
git update-ref refs/remotes/origin/lag master
git checkout -q -b ring master
printf '/* the slots */\n' >> lib/luaring.c
git commit -q -am slots || exit 1
git checkout -q -b reel master
printf '/* the hub */\n' >> lib/luareel.c
git commit -q -am hub || exit 1
git checkout -q -b coil master
printf 'LUNATIK_NEWLIB(coil, luacoil, &luacoil_class, NULL);\n' > lib/luacoil.c
git add lib && git commit -q -m coil || exit 1
git checkout -q -b spec master
sed -i 's|linux/foo.h|linux/foo_defs.h|' autogen/specs.lua
git commit -q -am spec || exit 1
git checkout -q -b docs master
printf 'A fifo of a page.\n' > README.md
git commit -q -am docs || exit 1
printf 'local spool = {}\n' > lib/spool.lua
printf 'LUNATIK_NEWLIB(spin, luaspin, &luaspin_class, NULL);\n' > lib/luaspin.c

printf 'local fifo = require("fifo")\n' > consumer/app.lua
printf 'local spool = require("spool")\n' > consumer/spooler.lua
printf 'local coil = require("coil")\n' > consumer/winder.lua
printf 'local spin = require("spin")\n' > consumer/spinner.lua
printf 'local foo = require("linux.foo")\n' > consumer/constants.lua
jq -n '{head: "bump", base: "master", body: "A fifo."}' > bump.json
mkdir -p sub
jq -n '{head: "docs", base: "master", body: "A fifo."}' > sub/docs.json
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

printf cases > key
mkdir -p keyed
cat > keyed/gh <<STUB
#!/bin/sh
[ "\$GH_TOKEN" = cases ] && exec "$PWD/stub/gh" "\$@"
exit 1
STUB
chmod +x keyed/gh

