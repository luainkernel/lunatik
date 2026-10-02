#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Reads the cases a spawned driver of the thread tests runs through tests.lib's
# test (see run.sh). Source it after lib.sh.

reported()
{
	dmesg_since | grep -qE "PASS[[:space:]]$1\$"
}

# verdict <case> <description>: tests.lib reports PASS and the name of each case that passed
verdict()
{
	if reported "$1"; then
		ktap_pass "$2"
	else
		ktap_fail "$2"
	fi
}

