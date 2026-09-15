# SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

BPF_CFLAGS = -target bpf -Wall -O2 -c -g

all: xdp_native.bpf.o xdp_verdict.bpf.o xdp_byte.bpf.o

vmlinux.h: /sys/kernel/btf/vmlinux
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

xdp_native.bpf.o: xdp_native.bpf.c bench.bpf.h vmlinux.h
	clang $(BPF_CFLAGS) -o $@ $<

xdp_verdict.bpf.o: xdp_lua.bpf.c bench.bpf.h vmlinux.h
	clang $(BPF_CFLAGS) -DLUNATIK_BENCH_RUNTIME='"bench/verdict"' -o $@ $<

xdp_byte.bpf.o: xdp_lua.bpf.c bench.bpf.h vmlinux.h
	clang $(BPF_CFLAGS) -DLUNATIK_BENCH_RUNTIME='"bench/byte"' -o $@ $<

clean:
	rm -f vmlinux.h xdp_native.bpf.o xdp_verdict.bpf.o xdp_byte.bpf.o

