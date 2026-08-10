# SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

all: https.o

vmlinux.h:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

https.o: https.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

clean:
	rm -f vmlinux.h https.o

