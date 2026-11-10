#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repositories push-guard.cases pushes from: <dir> holds one
# commit, written with a fixed author, committer and date so that its hash, which the cases name as a
# lease, is the same on every run, and <dir>/other is a repository of its own that does not hold it.
#
# Usage: bash tools/checks/cases/push-guard.fixture.sh <dir>

cd "$1" || exit 1
export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid GIT_AUTHOR_DATE='2026-01-01T00:00:00Z'
export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
git init -q -b master . && git commit -q --allow-empty -m root || exit 1
git init -q -b master other && git -C other commit -q --allow-empty -m other

