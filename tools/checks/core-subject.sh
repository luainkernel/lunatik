#!/bin/bash
# Checks that a commit touching the core says so in its subject: a core change
# every binding's runtime path goes through, riding inside a binding's commit,
# is invisible to whoever reads the history by subject. Heuristic: it nudges a
# review, it does not rewrite.
# Usage: core-subject.sh <file>...   with the commit subject on stdin
# Prints the finding; exits 1 when there is one. A file list carrying no core
# file, or carrying nothing else, is skipped silently, so callers can pass any
# commit's files.

iscore() {
	case "${1##*/}" in
		lunatik.h|lunatik_core.c|lunatik_obj.c|lunatik_val.c|lunatik_val.h|lunatik_aux.c|lunatik_run.c|lunatik_percpu.c|lunatik_percpu.h)
			return 0 ;;
	esac
	case "$1" in
		doc/capi.md|*/doc/capi.md) return 0 ;;
	esac
	return 1
}

core="" other=""
for f in "$@"; do
	if iscore "$f"; then core="$core  $f
"; else other="$f"; fi
done
[ -n "$core" ] && [ -n "$other" ] || exit 0

read -r subject
case "$subject" in
	lunatik*:*|core:*|capi:*|api:*) exit 0 ;;
esac
printf '%s\n' "$subject" | grep -qE 'lunatik[_.][A-Za-z_]|LUNATIK_[A-Z]|capi\.md|[Cc] API' && exit 0

printf '"%s" changes the core without saying so:\n%sA core change is its own commit, or its subject names the core it changes.\n' \
	"$subject" "$core"
exit 1

