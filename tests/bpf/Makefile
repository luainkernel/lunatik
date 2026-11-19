#
# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#

all: log.bpf.o

vmlinux.h: /sys/kernel/btf/vmlinux
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

log.bpf.o: log.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

clean:
	rm -f vmlinux.h log.bpf.o

