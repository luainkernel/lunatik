#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs the command guards over the cases each one was proved against, so a later change to a guard,
# or to commands.sh beneath them, is read against them again: tools/checks/cases/<guard>.cases holds
# one case a line, `block` or `pass`, a tab and the tool input the guard reads, a command unless a
# `# tool: Agent` or `# tool: Workflow` line names the subagent type or the script instead. Only the
# guards whose verdict the command alone decides have cases, none that asks GitHub, the device or the
# worktrees. Prints each wrong verdict and a count, and exits 1 when one is wrong.
#
# Usage: bash tools/checks/cases.sh [<cases file>...]   (default every file under tools/checks/cases)

dir=$(dirname "$0")
[ $# -gt 0 ] || set -- "$dir"/cases/*.cases

wrong=0
total=0
for cases in "$@"; do
	guard="$dir/$(basename "$cases" .cases).sh"
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
		jq -nc --arg tool "$tool" --arg field "$field" --arg value "$value" \
			'{tool_name: $tool, tool_input: {($field): $value}}' | bash "$guard" > /dev/null 2>&1
		rc=$?
		got=pass
		[ $rc -eq 2 ] && got=block
		total=$((total + 1))
		[ "$got" = "$want" ] && continue
		echo "$(basename "$guard"): wants $want, got $got: $value"
		wrong=$((wrong + 1))
	done < "$cases"
done
echo "cases: $((total - wrong)) of $total"
[ $wrong -eq 0 ]

