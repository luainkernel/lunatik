#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The heuristic checks over a change, which annotate a pull request and do not fail it: the file
# checks over the files it adds or modifies, read in the working tree against <base>, and the commit
# checks over each of its commits. Prints each check's lines under its name; --github prints them as
# the Checks workflow's annotations instead.
#
# Usage: bash tools/checks/advisory.sh [--github] <base> <head>

github=0
[ "$1" = "--github" ] && { github=1; shift; }
base=$1
head=$2
[ -n "$base" ] && [ -n "$head" ] || { echo "usage: advisory.sh [--github] <base> <head>" >&2; exit 2; }

dir=$(dirname "$0")
files=$(git diff --name-only --diff-filter=ACM "$base" "$head")
commits=$(git rev-list --reverse "$base..$head")

report() {
	[ -n "$2" ] || return 0
	if [ $github -eq 1 ]
	then
		echo "::warning title=$1::$(printf '%s' "$2" | sed ':a;N;$!ba;s/\n/%0A/g')"
	else
		printf '== %s\n%s\n' "$1" "$2"
	fi
}

for check in module-conventions comment-style comment-siblings idioms lua-style kthread function-shape core-helper deferral terminator shadowed-readers blast-radius examples-touched test-harness cppcheck-tests rename-orphaned recursion; do
	report "$check" "$(CHECK_BASE=$base bash "$dir/$check.sh" $files 2>&1)"
done

# a subject and a body belong to a commit, so these read each one
for check in core-subject kernel-answer; do
	report "$check" "$(for commit in $commits; do bash "$dir/$check.sh" "$commit" 2>&1; done)"
done
true

