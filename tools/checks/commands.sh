# Sourced by the command guards: what a tool command runs, read from the raw hook input, which
# embeds the command verbatim.

# the command field, closed by the first bare quote, escapes undone: a line of its own is a command
command_text() {
	printf '%s' "$1" | sed -E 's/^.*"command"[[:space:]]*:[[:space:]]*"//; s/([^\\])".*$/\1/; s/\\n/\n/g'
}

# a suite's run.sh as the command, bare or under sudo, bash or sh; a mention of the file, a path
# handed to git or to a check, is not a run, and the bare substring read every one of those as one
runs_suite() {
	command_text "$1" |
		grep -Eq '(^|[;&|(])[[:space:]]*((sudo|bash|sh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+)*([^[:space:]]*/)?run\.sh([[:space:]]|$|[;&|)"\\])'
}

