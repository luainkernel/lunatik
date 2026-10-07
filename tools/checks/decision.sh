#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A decision handed to the maintainer is one he takes in one read: what is to be decided, the
# options, and the recommendation with its reason. "Its rewording is the maintainer's" named who
# decides and not what, on #1205, and the maintainer had to ask what his decision was.
# Takes text files, a review body, a comment, a pull request or issue body or a reply; when one
# hands a decision over without the three, prints the lines that hand it over and exits 1.
#
# Usage: bash tools/checks/decision.sh <file>...

handoff='decis(a|ã)o (e |é )?(sua|dele|do maintainer)|fica (para|com) (voc(e|ê)|o maintainer)|a decis(a|ã)o fica (para|com) ele|voc(e|ê) decide|a escolha (e|é) (sua|dele)|cabe a (voc(e|ê)|ele)|levo (isso |isto )?(a|para) (voc(e|ê)|ele)|aguardo (a )?(sua )?decis|maintainer.s (call|decision)|is the maintainer.s|left to the maintainer|up to the maintainer|for the maintainer to (decide|choose|pick)|(your|his) (call|decision)[.,;:]|bring (it|this) (back )?to the maintainer'
question='o que decidir|a decidir:|decis(a|ã)o:|to decide:|decision:'
option='^[[:space:]>*-]*(\*\*)?(\(?[a-e]\)|op(c|ç)(a|ã)o [a-e1-9]|option [a-e1-9])'
recommend='recomend|recommend'

status=0
for file in "$@"; do
	[ -f "$file" ] || continue
	said=$(sed -E 's/"[^"]*"//g; s/`[^`]*`//g' "$file") # a phrase quoted is one talked about, not one said
	# a decision reported as taken hands nothing over
	said=$(printf '%s\n' "$said" | sed -E "s/\b(foi|por|was)( a| the)? ($handoff)//gI")
	printf '%s\n' "$said" | grep -qiE "$handoff" || continue
	missing=""
	grep -qiE "$question" "$file" || missing="$missing, what is to be decided"
	[ "$(grep -ciE "$option" "$file")" -ge 2 ] || missing="$missing, two options or more"
	grep -qiE "$recommend" "$file" || missing="$missing, a recommendation"
	[ -z "$missing" ] && continue
	printf '%s\n' "$said" | grep -niE "$handoff" | sed "s|^|$file:|"
	echo "$file: hands a decision over without${missing#,}; write \"Decision: <the question>\", options A) and B) with what each changes, and \"Recommendation: <option>, because <reason>\""
	status=1
done
exit $status

