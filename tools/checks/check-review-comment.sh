#!/usr/bin/env bash
# PreToolUse (Bash) hook: guard GitHub review/comment posts against a fixup
# reference given as a backtick'd SHA instead of a full commit URL. A backtick'd
# SHA renders as code on GitHub and does not link. Blocks (exit 2) only that
# specific, mechanical mistake; silent (exit 0) on everything else.
# Matches on the raw hook input: the command string is embedded in it verbatim
# (JSON escaping does not touch backticks or hex).

input=$(cat)

case "$input" in
	*"gh api"*reviews* | *"gh api"*comments*) ;;
	*) exit 0 ;;
esac

if printf '%s' "$input" | grep -Eq '`[0-9a-f]{7,40}'; then
	echo "check-review-comment: a fixup reference is a backtick'd SHA — GitHub renders it as code, not a link. Use a full commit URL instead: https://github.com/<owner>/<repo>/commit/<sha>" >&2
	exit 2
fi
exit 0


