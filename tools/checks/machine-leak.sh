#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A tracked file carries the tree, not the machine it was written on: an absolute
# path in a home directory, a password handed to sudo, a credential read out of a
# file or carried inside a URL, a literal shaped like a token, or the name of a
# private repository this tree cannot see. Whatever is committed is read by
# everyone who clones, and a credential committed once is a credential rotated.
#
# A gate, not a heuristic: any finding exits 1 and the commit fails. It prints the
# file, the line and the rule, never the text that matched, which would otherwise
# reach a terminal, a CI log and a pull request annotation. Binaries and files it
# cannot read are skipped, so callers can pass any path.
#
# The private repositories come from LUNATIK_CONSUMERS, the list consumers.sh
# already reads, and that rule is silent where the variable is unset: the names
# live on the machine holding the clones, the only one that can leak them.
#
# The working tree is read by default; CHECK_STAGED=1 reads the index instead, so
# the commit gate sees what is committed and not a file edited after staging.
#
# Usage: bash tools/checks/machine-leak.sh <file>...
#        CHECK_STAGED=1 bash tools/checks/machine-leak.sh <file>...

status=0

if [ -n "$CHECK_STAGED" ]; then
	staged=$(mktemp)
	trap 'rm -f "$staged"' EXIT
fi

quote() { sed 's/[][\.*+?(){}|^$]/\\&/g'; }

consumers=""
if [ -n "$LUNATIK_CONSUMERS" ]; then
	# a clone named after something this tree already carries would flag the tree itself
	tracked=$(git ls-files | tr '/' '\n' | sed -n 'p; s|\.[^.]*$||p' | sort -u)
	for dir in $(echo "$LUNATIK_CONSUMERS" | tr ':' ' '); do
		consumers="$consumers|$(printf '%s' "$dir" | quote)"
		base=$(basename "$dir")
		printf '%s\n' "$tracked" | grep -qxF "$base" && continue
		git grep -qIF -e "$base" HEAD >/dev/null 2>&1 && continue
		consumers="$consumers|(^|[^[:alnum:]_])$(printf '%s' "$base" | quote)([^[:alnum:]_]|$)"
	done
	consumers=${consumers#|}
fi

scan() {	# rule, pattern, what the rule says
	local n
	for n in $(grep -nIE "$2" "$src" | cut -d: -f1); do
		echo "$file:$n: $1: $3"
		status=1
	done
}

for file in "$@"; do
	if [ -n "$CHECK_STAGED" ]; then
		git show ":$file" > "$staged" 2>/dev/null || continue
		src=$staged
	else
		[ -f "$file" ] || continue
		src=$file
	fi

	scan home-path '/(home|Users)/[A-Za-z0-9._-]+|/root/[A-Za-z0-9._-]+' \
		'an absolute path in a home directory names one machine; take it from an argument or $HOME'
	scan sudo-password 'sudo([[:space:]]+-[[:alnum:]]+)*[[:space:]]+-[A-Za-z]*S|pass(word|wd)[[:space:]]*(is|=|:)' \
		'a password handed to sudo; a machine that needs one says so in its own untracked notes'
	scan credential-file '\$\([[:space:]]*(cat|head|tr)[^)]*(token|secret|credential|passwd)' \
		'a credential read out of a file; take it from the environment, as GH_TOKEN is taken'
	scan url-credential '://[^/[:space:]]+:[^/[:space:]@]+@' \
		'a credential carried inside a URL'
	scan secret-literal 'gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{12,}|-----BEGIN [A-Z ]*PRIVATE KEY-----' \
		'a literal shaped like a credential'
	[ -n "$consumers" ] && scan consumer-clone "$consumers" \
		'names a repository from $LUNATIK_CONSUMERS; a clone this tree cannot see is named nowhere in it'
done

exit $status

