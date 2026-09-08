#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Runs data regression tests and reports aggregated KTAP results.
#
# Usage: sudo bash tests/data/run.sh

DIR="$(dirname "$(readlink -f "$0")")"

RESULT=0
bash "$DIR/resize_atomic.sh" || RESULT=1
exit $RESULT

