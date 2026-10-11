#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the command guards over the cases each one was proved against, so a later change to a guard,
# or to commands.sh beneath them, is read against them again: tools/checks/cases/<guard>.cases holds
# one case a line, `block` or `pass`, a tab and the tool input the guard reads, a command unless a
# `# tool: Agent` or `# tool: Workflow` line names the subagent type or the script instead. Only the
# guards whose verdict the command decides, alone or with the repository it runs in, have cases, none
# that asks GitHub, the device or the worktrees; <guard>.fixture.sh, beside the cases of one that reads
# the repository, builds it in a scratch directory the cases run in. Prints each wrong verdict and a
# count, and exits 1 when one is wrong.
#
# Usage: bash tools/checks/cases.sh [<cases file>...]   (default every file under tools/checks/cases)

dir=$(dirname "$0")
[ $# -gt 0 ] || set -- "$dir"/cases/*.cases
# shellcheck disable=SC2046 # git rebase -x and a hook export GIT_DIR, where a fixture would write
unset $(git rev-parse --local-env-vars)

wrong=0
total=0
for cases in "$@"; do
	guard="$dir/$(basename "$cases" .cases).sh"
	fixture=${cases%.cases}.fixture.sh
	cwd=
	if [ -f "$fixture" ]; then
		cwd=$(mktemp -d)
		bash "$fixture" "$cwd" > /dev/null 2>&1 || { rm -rf "$cwd"; echo "$(basename "$fixture"): fails"; exit 1; }
	fi
	tool=Bash
	while IFS=$'\t' read -r want value; do
		case "$want" in
			"# tool: "*) tool=${want#\# tool: }; continue ;;
			""|"#"*) continue ;;
		esac
		case "$tool" in
			Agent) field=subagent_type ;;
			Workflow) field=script ;;
			*) field=command ;;
		esac
		jq -nc --arg tool "$tool" --arg field "$field" --arg value "$value" --arg cwd "$cwd" \
			'{tool_name: $tool, tool_input: {($field): $value}} + if $cwd == "" then {} else {cwd: $cwd} end' |
			bash "$guard" > /dev/null 2>&1
		rc=$?
		got=pass
		[ $rc -eq 2 ] && got=block
		total=$((total + 1))
		[ "$got" = "$want" ] && continue
		echo "$(basename "$guard"): wants $want, got $got: $value"
		wrong=$((wrong + 1))
	done < "$cases"
	[ -z "$cwd" ] || rm -rf "$cwd"
done
echo "cases: $((total - wrong)) of $total"
[ $wrong -eq 0 ]

