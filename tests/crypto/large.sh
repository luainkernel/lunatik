#!/bin/bash
#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#
# crypto.skcipher(), crypto.aead() and crypto.comp() take a copy of their input in one kmalloc
# block: a scatterlist maps linear memory, and a process runtime's strings come from kvmalloc, which
# hands out vmalloc memory past a page whenever kmalloc fails and always past KMALLOC_MAX_SIZE.
#
# Data of two pages and a block, and associated data of two pages and a byte, go through the copy
# whole: cbc(aes) over the data matches cbc(aes) over each page chained by its last block, gcm(aes)
# seals the data into what ctr(aes) gives from the second counter and opens it back under the
# associated data, and a byte flipped in the last page of either fails the tag. lz4 compresses data
# of a page and a block, and of 128 KiB, to fewer bytes and decompresses it back whole. Past 128 KiB,
# 131073 bytes lz4 shrinks, and 131072 bytes of cbc(aes) ciphertext it cannot, given an output of
# LZ4_COMPRESSBOUND, raise EINVAL on 6.14 and earlier, where scomp bounds the input and the output by
# its 128 KiB scratch (crypto/scompress.c), and round-trip on 6.15 and later, the ciphertext's output
# past 128 KiB as well. A string past KMALLOC_MAX_SIZE, which kvmalloc always takes from
# vmalloc, is refused with "not enough memory" as the data of skcipher's encrypt and decrypt, of
# aead's and of comp's compress and decompress, as aead's associated data and as the output size of
# comp's, whose block holds the output too, and run_test reads no WARNING in dmesg, the copy asking
# kmalloc for none. This script writes the page size, KMALLOC_MAX_SIZE, which lib.sh's kmalloc_max
# reads from /proc/buddyinfo, and whether the running release is 6.14 or earlier into large_sizes.lua
# for the case.
#
# A build that maps the string itself hands the cipher a struct page virt_to_page() made up from a
# vmalloc address, which arm64 reads when the walk flushes a page it wrote, an oops under the
# runtime's lock. The case runs only when the loaded luacrypto lists the copy's allocator,
# luacrypto_newbuffer, in /proc/kallsyms, and skips where the kernel serves cbc(aes), gcm(aes),
# ctr(aes) or lz4 not at all, which the script allocates before its cases and names.
#
# Usage: sudo bash tests/crypto/large.sh

SCRIPT=tests/crypto/large
MODULE=luacrypto
COPY=luacrypto_newbuffer
SIZES=/lib/modules/lua/tests/crypto/large_sizes.lua

source "$(dirname "$(readlink -f "$0")")/../lib.sh"

cleanup() {
	lunatik stop "$SCRIPT" > /dev/null 2>&1
	rm -f "$SIZES"
}
trap cleanup EXIT
cleanup

ktap_header
ktap_plan 1

grep -Eq " $COPY[[:space:]]\[$MODULE\]$" /proc/kallsyms 2> /dev/null || {
	ktap_skip "crypto/large: the loaded $MODULE does not list $COPY: it would map a vmalloc string"
	ktap_totals
	exit 0
}

page=$(getconf PAGESIZE)
bounded=false
printf '6.15\n%s\n' "$(uname -r)" | sort -CV || bounded=true
printf 'return {page = %d, kmalloc = %d, bounded = %s}\n' "$page" "$(kmalloc_max)" "$bounded" > "$SIZES"

served_case "crypto/large" run_test "$SCRIPT"
ktap_totals

