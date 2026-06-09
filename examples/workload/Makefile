# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only
#

all: vmlinux scheduler.o

vmlinux:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

scheduler.o: scheduler.c
	clang -target bpf -Wall -O2 \
		-D__SCX_COMPAT_BPF_H \
		-Wno-visibility \
		-I. -I./scx/scheds/include -c -g $<

clean:
	rm -f vmlinux.h scheduler.o

