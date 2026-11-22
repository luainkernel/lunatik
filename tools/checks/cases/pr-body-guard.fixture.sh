#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Builds, in the empty directory <dir>, the repository the harness's pr-body-guard.fixture.sh builds,
# with Lunatik's examples-named.sh and the examples-touched.sh and modules.sh it runs in its
# tools/checks, where the guard reads the examples of a pull request of that checkout.
#
# Usage: bash tools/checks/cases/pr-body-guard.fixture.sh <dir>

checks=$(cd "$(dirname "$0")/.." && pwd)
bash "$checks/../../harness/tools/checks/cases/pr-body-guard.fixture.sh" "$1" || exit 1
mkdir -p "$1/tools/checks" || exit 1
cp "$checks/examples-named.sh" "$checks/examples-touched.sh" "$checks/modules.sh" "$1/tools/checks/"

