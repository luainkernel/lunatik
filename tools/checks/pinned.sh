#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# With lunatik_run gone no state is left to hold a module, so a reference a Lunatik module keeps past
# its holders is one nothing can drop: the module stays loaded until a reboot, and a build whose
# symbols differ cannot load beside it. #1462's build left luarcu and lunatik that way after one batch
# of examples, and the cycles that followed on the pinned host took them from 2 and 9 references past
# their holders to 25 and 33. Prints each such module with those references and exits 1, silent
# otherwise; LUNATIK_SYSFS names another tree than /sys, for the check's own proof.

sys=${LUNATIK_SYSFS:-/sys}/module
[ -d "$sys/lunatik_run" ] && exit 0

held=
for module in "$sys"/lunatik "$sys"/lua*; do
	[ -f "$module/refcnt" ] || continue
	free=$(($(cat "$module/refcnt") - $(ls "$module/holders" 2>/dev/null | wc -l)))
	[ "$free" -gt 0 ] && held="$held ${module##*/}=$free"
done
[ -n "$held" ] || exit 0

echo "pinned: with lunatik_run gone these modules keep references past their holders, which only a reboot drops:$held"
exit 1

