#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#

# a kprobe reads its arguments from the registers of the kernel's architecture, named as
# tools/scripts/Makefile.arch names it
ARCH := $(shell uname -m | sed -e s/i.86/x86/ -e s/x86_64/x86/ \
                               -e s/sun4u/sparc/ -e s/sparc64/sparc/ \
                               -e /arm64/!s/arm.*/arm/ -e s/sa110/arm/ \
                               -e s/s390x/s390/ -e s/parisc64/parisc/ \
                               -e s/ppc.*/powerpc/ -e s/mips.*/mips/ \
                               -e s/sh[234].*/sh/ -e s/aarch64.*/arm64/ \
                               -e s/riscv.*/riscv/ -e s/loongarch.*/loongarch/)

all: fallback.bpf.o

vmlinux.h: /sys/kernel/btf/vmlinux
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

fallback.bpf.o: fallback.bpf.c vmlinux.h
	clang -target bpf -D__TARGET_ARCH_$(ARCH) -DPAGE_SIZE=$(shell getconf PAGESIZE) -Wall -O2 -c -g $<

clean:
	rm -f vmlinux.h fallback.bpf.o

