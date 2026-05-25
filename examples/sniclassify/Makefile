# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only

all: vmlinux classify.o

vmlinux:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

classify.o: classify.c
	clang -target bpf -Wall -O2 -c -g $<

clean:
	rm -f vmlinux.h classify.o

