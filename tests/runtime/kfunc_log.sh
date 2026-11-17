#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# bpf_lunatik_log, the kfunc lunatik.ko registers on the common hook, reaches a program of a type
# other than XDP and TC: a syscall program calls it and loads, and runs under bpftool prog run,
# attached nowhere, as lunatik_logs in tests/lib.sh runs the xdp and tc log cases: one run logs its
# line once and none of the bytes past the size it passes, and 30 runs more stop at the rate
# limit's burst. That the kfunc defers its write, which a program under the runqueue lock needs, is
# unproved by a case: its failure is a deadlock, which a program on a scheduler hook would risk on
# the host. BPF_PROG_TEST_RUN of a syscall program takes no data and refuses a repeat, which
# bpftool sets to 1 unless told 0.
#
# Usage: sudo bash tests/runtime/kfunc_log.sh

DIR="$(dirname "$(readlink -f "$0")")"
PIN="/sys/fs/bpf/lunatik_kfunc_log"
TITLE="kfunc log: a syscall program logs through bpf_lunatik_log, within its size and rate limit"

source "$DIR/../lib.sh"

cleanup() { rm -f "$PIN"; }

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

command -v bpftool > /dev/null 2>&1 || skip_script "$TITLE (bpftool not available)"
command -v clang > /dev/null 2>&1 || skip_script "$TITLE (clang not available)"
make -C "$DIR" > /dev/null || fail "failed to build the syscall program"

lunatik_logs "$DIR/kfunc_log.bpf.o" "$PIN" "kfunc log: a line from a syscall program" "$TITLE" repeat 0

ktap_totals

