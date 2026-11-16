#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests the creation of a hardirq runtime by each route a script takes to it, the CLI's
# `run -c hardirq`, `lunatik.runtime` and `lunatik.percpu`. On a kernel built with
# CONFIG_PREEMPT_RT, where spin_lock_irqsave sleeps, each is refused with the message the
# core raises, before the script's body prints its mark, and the refused run leaves nothing
# registered; elsewhere each creates the runtime and its body runs. The kernel's build is read
# from `uname -v`, which names PREEMPT_RT where the kernel was built with it (init/Makefile),
# whether or not the kernel installs its configuration.
#
# Usage: sudo bash tests/runtime/hardirq.sh

SCRIPT="tests/runtime/hardirq"
MARK="tests/runtime/hardirq: body ran"
REFUSAL="hardirq runtime not allowed on PREEMPT_RT, where a spinlock sleeps"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

preemptrt() { [[ " $(uname -v) " == *" PREEMPT_RT "* ]]; }

# what the run of a case did that this kernel should not: nothing on PREEMPT_RT when it was
# refused, nothing elsewhere when it created the runtime
verdict()
{
	if preemptrt; then
		[ "$status" -eq 1 ] && [ "$err" = "lunatik: $REFUSAL" ] || echo "not refused (status $status): $err"
		[ "$ran" -eq 0 ] || echo "the body ran before the refusal"
		case "$listed" in
			*"$SCRIPT"*) echo "the refused run left the script registered" ;;
		esac
	else
		[ "$status" -eq 0 ] && [ -z "$err" ] || echo "failed (status $status): $err"
		[ "$ran" -ge 1 ] || echo "the body did not run"
	fi
}

# route <case> <lunatik argument>...: runs the CLI with the arguments and reads its verdict
route()
{
	local name=$1 before listed ran why
	shift
	before=$(dmesg_since | grep -cF "$MARK")
	cli "$@"
	listed=$(lunatik list)
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	ran=$(($(dmesg_since | grep -cF "$MARK") - before))
	why=$(verdict)
	if [ -z "$why" ]; then
		ktap_pass "$name"
	else
		comment "$why"
		ktap_fail "$name"
	fi
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 4
if preemptrt; then
	echo "# PREEMPT_RT: each route is refused"
else
	echo "# no PREEMPT_RT: each route creates the runtime"
fi

mark_dmesg

route "hardirq: run -c hardirq" run -c hardirq "$SCRIPT"
route "hardirq: lunatik.runtime" -e "lunatik.runtime('$SCRIPT', 'hardirq'):stop()"
route "hardirq: lunatik.percpu" -e "lunatik.percpu('$SCRIPT', 'hardirq'):stop()"

check_dmesg && ktap_pass "no Lua errors, kernel warnings or oopses"

ktap_totals

