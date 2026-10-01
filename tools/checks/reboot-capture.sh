#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# A reboot clears /tmp, where every session keeps its scratch files, and takes the oops and the
# pinned modules with it. tools/prereboot.sh saves them for every session on the host, so the session
# that asks for the reboot runs it: the others learn of the reboot when it is done. A session asked for
# one on 2026-10-01 and the reboot took another session's cycle scripts and drafts.
# Takes text files, a reply; when one asks for a reboot and the checkout holds no scratch/reboot-*
# capture taken in the last hour, prints the lines that ask and exits 1.
#
# Usage: bash tools/checks/reboot-capture.sh <file>...

ask='(pe(c|ç)o|pedir|pedindo|pede) (o |um )?(reboot|rein(i|í)cio)|precis[a-z]* (de )?(um )?(reboot|reinici)|s(o|ó) (um )?(reboot|rein(i|í)cio) (resolve|limpa|tira)|(needs?|requires?|asks? for|asking for) a reboot|only a reboot|reboot (is|é|e) (the maintainer|seu|sua|do maintainer)'

common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
project=${common:+$(dirname "$common")}
project=${project:-${CLAUDE_PROJECT_DIR:-$PWD}}
[ -n "$(find "$project/scratch" -maxdepth 1 -name 'reboot-*' -mmin -60 2>/dev/null)" ] && exit 0

status=0
for file in "$@"; do
	[ -f "$file" ] || continue
	said=$(sed -E 's/"[^"]*"//g; s/`[^`]*`//g' "$file") # a phrase quoted is one talked about, not one said
	printf '%s\n' "$said" | grep -qiE "$ask" || continue
	printf '%s\n' "$said" | grep -niE "$ask" | sed "s|^|$file:|"
	echo "$file: asks for a reboot with no capture taken in the last hour; run bash tools/prereboot.sh first, which saves every session's /tmp, the oops and the pinned modules under scratch/reboot-<time>/"
	status=1
done
exit $status

