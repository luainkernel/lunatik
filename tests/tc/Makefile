# SPDX-FileCopyrightText: (c) 2026 Ashwani Kumar Kamal <ashwanikamal.im421@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only

all: tc_pass.bpf.o tc_drop.bpf.o tc_detach.bpf.o tc_zerokey.bpf.o tc_reattach.bpf.o

vmlinux.h:
	bpftool btf dump file /sys/kernel/btf/vmlinux format c > $@

tc_pass.bpf.o: tc_pass.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

tc_drop.bpf.o: tc_drop.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

tc_detach.bpf.o: tc_detach.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

tc_zerokey.bpf.o: tc_zerokey.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

tc_reattach.bpf.o: tc_reattach.bpf.c vmlinux.h
	clang -target bpf -Wall -O2 -c -g $<

clean:
	rm -f vmlinux.h tc_pass.bpf.o tc_drop.bpf.o tc_detach.bpf.o tc_zerokey.bpf.o tc_reattach.bpf.o

