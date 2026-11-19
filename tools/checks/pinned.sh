#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# With lunatik_run gone no Lunatik state is left to hold a module, so a reference a Lunatik module keeps
# past its holders is one Lunatik cannot drop, and a build whose symbols differ cannot load beside it.
# #1462's build left luarcu and lunatik that way after one batch of examples, and the cycles that
# followed on the pinned host took them from 2 and 9 references past their holders to 25 and 33: a
# leak, which only a reboot clears. A loaded eBPF program that calls one of the module's kfuncs holds
# such a reference too, which the verifier takes (btf_try_get_module, kernel/bpf/verifier.c) and drops
# when the program is freed, so removing what keeps it loaded, its pin, its link or its tc or XDP
# attachment, frees it. Prints each such module with those references and the way to tell the two
# apart, and exits 1, silent otherwise; LUNATIK_SYSFS names another tree than /sys, for the check's
# own proof.

sys=${LUNATIK_SYSFS:-/sys}/module
[ -d "$sys/lunatik_run" ] && exit 0

held=
for module in "$sys"/lunatik "$sys"/lua*; do
	[ -f "$module/refcnt" ] || continue
	free=$(($(cat "$module/refcnt") - $(ls "$module/holders" 2>/dev/null | wc -l)))
	[ "$free" -gt 0 ] && held="$held ${module##*/}=$free"
done
[ -n "$held" ] || exit 0

echo "pinned: with lunatik_run gone these modules keep references past their holders:$held"
echo "pinned: an eBPF program that calls a kfunc of one holds it until the program is freed; 'sudo bpftool -f prog show' lists the programs with their pins and 'sudo bpftool net show' their tc and XDP attachments, and removing what keeps a program loaded frees it; a reference no program holds only a reboot drops"
exit 1

