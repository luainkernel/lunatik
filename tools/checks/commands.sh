# Sourced by the command guards, lunatik-lock.sh and crash-guard.sh: what a tool command runs,
# read from the raw hook input, which embeds the command verbatim.

# a suite's run.sh as the command, bare or under sudo, bash or sh; a mention of the file, a path
# handed to git or to a check, is not a run, and the bare substring read every one of those as one
runs_suite() {
	# the command field with its escapes undone: a line of its own is a command, an escaped quote is not
	printf '%s' "$1" | sed -E 's/^.*"command"[[:space:]]*:[[:space:]]*"//; s/\\n/\n/g' |
		grep -Eq '(^|[;&|(])[[:space:]]*((sudo|bash|sh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+)*([^[:space:]]*/)?run\.sh([[:space:]]|$|[;&|)"\\])'
}

