# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only

all: xdp_pass.bpf.o xdp_drop.bpf.o xdp_detach.bpf.o xdp_zerokey.bpf.o

vmlinux.h:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

xdp_pass.bpf.o: xdp_pass.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

xdp_drop.bpf.o: xdp_drop.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

xdp_detach.bpf.o: xdp_detach.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

xdp_zerokey.bpf.o: xdp_zerokey.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

clean:
	rm -f vmlinux.h xdp_pass.bpf.o xdp_drop.bpf.o xdp_detach.bpf.o xdp_zerokey.bpf.o

