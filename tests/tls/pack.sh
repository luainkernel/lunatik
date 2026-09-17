#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# Tests tls.pack(), the crypto_info assembler setsockopt(SOL_TLS) takes: every
# cipher linux.tls.cipher carries packs to the length do_tls_setsockopt_conf
# demands of it, the header and the key material land at the offsets the
# tls12_crypto_info_* structs place them at, a part of the wrong length is
# refused naming it, and a cipher outside TLS_CIPHER_MIN..MAX is refused. The
# module itself is pinned too: tls.pack, the two version numbers uapi/linux/tls.h
# composes from halves autogen cannot read, the seven record types, the
# close_notify helper, and nothing else.
#
# Pure Lua: no socket, no CONFIG_TLS and no ULP, so nothing here is skipped.
#
# Usage: sudo bash tests/tls/pack.sh

SCRIPT="tests/tls/pack"

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup()
{
	lunatik stop "$SCRIPT" > /dev/null 2>&1
}

trap cleanup EXIT
cleanup

ktap_header
ktap_plan 5

mark_dmesg
run_script "$SCRIPT"
check_dmesg || { ktap_totals; exit 1; }

dmesg_since | grep -q "tls pack: the module carries the packer, the versions and the record types" ||
	fail "the tls module is not the surface it documents"
ktap_pass "pack: the module carries tls.pack, the versions, the record types and close_notify, and nothing else"

dmesg_since | grep -q "tls pack: every cipher sized" || fail "a cipher packed to the wrong length"
ktap_pass "pack: every cipher packs to the length its crypto_info struct has"

dmesg_since | grep -q "tls pack: fields in order" || fail "the header or the key material is misplaced"
ktap_pass "pack: the header and the key material sit where the kernel reads them"

dmesg_since | grep -q "tls pack: wrong length refused" || fail "a part of the wrong length was accepted"
ktap_pass "pack: a part of the wrong length is refused, naming it"

dmesg_since | grep -q "tls pack: unknown cipher refused" || fail "an unknown cipher was accepted"
ktap_pass "pack: the accepted ciphers are exactly the ones linux.tls.cipher carries"

ktap_totals

