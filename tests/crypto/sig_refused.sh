#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.sig raises EINVAL for a name its template refuses, hmac(sha256), whose template builds a hash,
# where the kernel hands the template's error to the allocation, 6.12 and later, and ENOENT where it
# does not, 6.11 and earlier, and on 6.13, where the binding's crypto_has_alg check before the
# allocation answers every lookup that fails. This script writes the errno the running release gives
# into sig_refused_errno.lua for the case, and skips where the kernel serves no hmac(sha256), which the
# script allocates before its case and names.
#
# Usage: sudo bash tests/crypto/sig_refused.sh

SCRIPT=tests/crypto/sig_refused
ERRNO=/lib/modules/lua/tests/crypto/sig_refused_errno.lua

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	rm -f "$ERRNO"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

release=$(uname -r)
refused=EINVAL
if ! printf '6.12\n%s\n' "$release" | sort -CV || [[ "$release" == 6.13.* ]]; then
	refused=ENOENT
fi
printf 'return "%s"\n' "$refused" > "$ERRNO"

served_case "crypto/sig_refused" run_test "$SCRIPT"
ktap_totals

