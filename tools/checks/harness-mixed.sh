#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# The harness is the rules, the checks, the workflows and the skills. A commit that
# carries one of those together with code or tests hides it: the reviewer reads the
# feature, the rule lands unread, and a maintainer who wants one without the other
# has nothing to pick. AGENTS.md sanctions harness artifacts travelling together in
# one pull request; it does not sanction them riding inside an implementation.
#
# Reads commits, not files, since the mixing is a property of a commit: takes commits
# or a rev-range (bash tools/checks/harness-mixed.sh origin/master..HEAD), default HEAD.
# Over the last 400 commits of master it fires on 9, three of them the shape it is for;
# the rest are documentation sweeps that correct one wording in AGENTS.md and in the
# README at once, and a CI change whose README claim moved with it. Heuristic: it
# nudges a review, it does not rewrite.
#
# With --outside, reads paths on stdin and prints those that are not the harness, which
# merge-guard.sh reads a pull request's files with.

kind() {
	case "$1" in
		tools/shade.sh|tools/debian_kernel_postinst_lunatik.sh) echo other ;; # a user's tool, not the harness
		AGENTS.md|CLAUDE.md|.luarc.json|tools/*|.agents/*|.github/*|.claude/*) echo harness ;;
		.gitignore|.gitmodules|.editorconfig|LICENSE) echo neither ;; # neither, and in both kinds of commit
		*) echo other ;;
	esac
}

if [ "$1" = --outside ]; then
	while IFS= read -r f; do
		[ -z "$f" ] || [ "$(kind "$f")" = harness ] || printf '%s\n' "$f"
	done
	exit 0
fi

status=0

for commit in $(git rev-list --no-walk "${@:-HEAD}"); do
	harness="" other=""
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		case "$(kind "$f")" in
			harness) harness="$harness  $f
" ;;
			other) other=$f ;;
		esac
	done < <(git show --name-only --format= "$commit")
	[ -n "$harness" ] && [ -n "$other" ] || continue

	printf '%s "%s" mixes the harness into a change of its own:\n%s' "${commit:0:9}" \
		"$(git show -s --format=%s "$commit")" "$harness"
	status=1
done

[ $status -eq 0 ] || echo "the harness of one incident is its own commit, and its own pull request"
exit $status

