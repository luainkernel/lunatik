# SPDX-FileCopyrightText: (c) 2023-2024 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

all: vmlinux https.o

vmlinux:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

https.o: https.c
	clang -target bpf -Wall -O2 -c -g $<

clean:
	rm -f vmlinux.h https.o

