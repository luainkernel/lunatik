#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A core change every binding's runtime path goes through, riding inside a
# binding's commit, is invisible to whoever reads the history by subject: #848
# shipped the lock-owner scheme in lunatik.h and doc/capi.md under "fsnotify:
# watch filesystem events from Lua". The rule is not that core and a binding
# never mix, which AGENTS.md sanctions; it is that the subject says so.
#
# This one reads commits, not files, since a subject belongs to a commit and
# the staged diff the other checks read cannot see commit boundaries. The core
# is what the Layout table names, plus the C API reference, so there is no list
# to keep. Over the last 400 commits of master it fires on 7, four of them the
# shape it is for; the rest are docs and autogen sweeps whose only core file is
# doc/capi.md, which stays in because dropping it blinds the check to a new C
# API entry. Heuristic: it nudges a review, it does not rewrite.
#
# Usage: bash tools/checks/core-subject.sh <commit or range>...   (default HEAD)

status=0

for commit in $(git rev-list --no-walk "${@:-HEAD}"); do
	core="" other=""
	while IFS= read -r f; do
		case "$f" in
			lunatik.h|lunatik_*.c|doc/capi.md) core="$core  $f
" ;;
			"") ;;
			*) other=$f ;;
		esac
	done < <(git show --name-only --format= "$commit")
	[ -n "$core" ] && [ -n "$other" ] || continue

	subject=$(git show -s --format=%s "$commit")
	case "$subject" in lunatik*:*|core:*|capi:*|api:*) continue ;; esac
	grep -qE 'lunatik[_.][A-Za-z_]|LUNATIK_[A-Z]|capi\.md|[Cc] API' <<< "$subject" && continue

	printf '%s "%s" changes the core without saying so:\n%s' "${commit:0:9}" "$subject" "$core"
	status=1
done

[ $status -eq 0 ] || echo "a core change is its own commit, or its subject names the core it changes"
exit $status

