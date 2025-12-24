# SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

KERNEL_RELEASE ?= ${shell uname -r}
MODULES_PATH := /lib/modules
MODULES_RELEASE_PATH := ${MODULES_PATH}/${KERNEL_RELEASE}
MODULES_ORDER_LIST := kernel/zfs/zfs.ko kernel/zfs/zlua.ko updates/dkms/zfs.ko updates/dkms/zlua.ko # needed when zfs module is installed
MODULES_ORDER_FILE := ${MODULES_RELEASE_PATH}/modules.order
BTF_INSTALL_PATH = ${MODULES_RELEASE_PATH}/build
MODULES_BUILD_PATH ?= ${BTF_INSTALL_PATH}
MODULES_INSTALL_PATH := ${MODULES_RELEASE_PATH}/kernel
SCRIPTS_INSTALL_PATH := ${MODULES_PATH}/lua


LUNATIK_INSTALL_PATH = /usr/local/sbin
LUNATIK_EBPF_INSTALL_PATH = /usr/local/lib/bpf/lunatik
MOONTASTIK_RELEASE ?= v0.1c
LUA_API = lua/lua.h lua/lauxlib.h lua/lualib.h
RM = rm -f
MKDIR = mkdir -p -m 0755
INSTALL = install -o root -g root

all: lunatik_sym.h
	${MAKE} -C ${MODULES_BUILD_PATH} M=${PWD} CONFIG_LUNATIK=m	\
	CONFIG_LUNATIK_RUN=m CONFIG_LUNATIK_RUNTIME=y CONFIG_LUNATIK_DEVICE=m	\
	CONFIG_LUNATIK_LINUX=m CONFIG_LUNATIK_NOTIFIER=m CONFIG_LUNATIK_SOCKET=m \
	CONFIG_LUNATIK_RCU=m CONFIG_LUNATIK_THREAD=m CONFIG_LUNATIK_FIB=m \
	CONFIG_LUNATIK_DATA=m CONFIG_LUNATIK_PROBE=m CONFIG_LUNATIK_SYSCALL=m \
	CONFIG_LUNATIK_XDP=m CONFIG_LUNATIK_FIFO=m CONFIG_LUNATIK_XTABLE=m \
	CONFIG_LUNATIK_NETFILTER=m CONFIG_LUNATIK_COMPLETION=m \
	CONFIG_LUNATIK_CRYPTO_SHASH=m CONFIG_LUNATIK_CRYPTO_SKCIPHER=m \
	CONFIG_LUNATIK_CRYPTO_AEAD=m CONFIG_LUNATIK_CRYPTO_RNG=m \
	CONFIG_LUNATIK_CRYPTO_COMP=m CONFIG_LUNATIK_CPU=m CONFIG_LUNATIK_HID=m

clean:
	${MAKE} -C ${MODULES_BUILD_PATH} M=${PWD} clean
	${MAKE} -C examples/filter clean
	${RM} lunatik_sym.h

scripts_install:
	${MKDIR} ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/lunatik
	${MKDIR} ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/socket
	${MKDIR} ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/syscall
	${MKDIR} ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/crypto
	${INSTALL} -m 0644 driver.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/mailbox.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/net.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/util.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/lunatik/*.lua ${SCRIPTS_INSTALL_PATH}/lunatik
	${INSTALL} -m 0644 lib/socket/*.lua ${SCRIPTS_INSTALL_PATH}/socket
	${INSTALL} -m 0644 lib/syscall/*.lua ${SCRIPTS_INSTALL_PATH}/syscall
	${INSTALL} -m 0644 lib/crypto/*.lua ${SCRIPTS_INSTALL_PATH}/crypto
	${INSTALL} -m 0755 bin/lunatik ${LUNATIK_INSTALL_PATH}

scripts_uninstall:
	${RM} ${SCRIPTS_INSTALL_PATH}/driver.lua
	${RM} ${SCRIPTS_INSTALL_PATH}/runner.lua
	${RM} ${SCRIPTS_INSTALL_PATH}/mailbox.lua
	${RM} ${SCRIPTS_INSTALL_PATH}/net.lua
	${RM} -r ${SCRIPTS_INSTALL_PATH}/lunatik
	${RM} -r ${SCRIPTS_INSTALL_PATH}/socket
	${RM} -r ${SCRIPTS_INSTALL_PATH}/syscall
	${RM} ${LUNATIK_INSTALL_PATH}/lunatik

.PHONY: ebpf
ebpf:
	${MAKE} -C examples/filter

ebpf_install:
	${MKDIR} ${LUNATIK_EBPF_INSTALL_PATH}
	${INSTALL} -m 0644 examples/filter/https.o ${LUNATIK_EBPF_INSTALL_PATH}/

ebpf_uninstall:
	${RM} -r ${LUNATIK_EBPF_INSTALL_PATH}

examples_install:
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/examples
	${INSTALL} -m 0644 examples/*.lua ${SCRIPTS_INSTALL_PATH}/examples
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/examples/echod
	${INSTALL} -m 0644 examples/echod/*.lua ${SCRIPTS_INSTALL_PATH}/examples/echod
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/examples/filter
	${INSTALL} -m 0644 examples/filter/*.lua ${SCRIPTS_INSTALL_PATH}/examples/filter
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/examples/dnsblock
	${INSTALL} -m 0644 examples/dnsblock/*.lua ${SCRIPTS_INSTALL_PATH}/examples/dnsblock
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/examples/dnsdoctor
	${INSTALL} -m 0644 examples/dnsdoctor/*.lua ${SCRIPTS_INSTALL_PATH}/examples/dnsdoctor

examples_uninstall:
	${RM} -r ${SCRIPTS_INSTALL_PATH}/examples

tests_install:
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/tests
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/tests/rcumap_sync
	${INSTALL} -m 0644 tests/rcumap_sync/*.lua ${SCRIPTS_INSTALL_PATH}/tests/rcumap_sync
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/tests/crypto
	${INSTALL} -m 0644 tests/crypto/*.lua ${SCRIPTS_INSTALL_PATH}/tests/crypto

tests_uninstall:
	${RM} -r ${SCRIPTS_INSTALL_PATH}/tests

modules_install:
	${MKDIR} ${MODULES_INSTALL_PATH}/lunatik
	${INSTALL} -m 0644 *.ko lib/*.ko ${MODULES_INSTALL_PATH}/lunatik

btf_install:
	cp /sys/kernel/btf/vmlinux ${BTF_INSTALL_PATH}

modules_uninstall:
	${RM} -r ${MODULES_INSTALL_PATH}/lunatik

install: scripts_install modules_install
	for mod in $(MODULES_ORDER_LIST); do \
		grep -qxF "$$mod" $(MODULES_ORDER_FILE) || echo "$$mod" >> $(MODULES_ORDER_FILE); \
	done
	depmod -a

uninstall: scripts_uninstall modules_uninstall
	for mod in $(MODULES_ORDER_LIST); do \
		sed -i "\|^$$mod$$|d" $(MODULES_ORDER_FILE); \
	done
	depmod -a

lunatik_sym.h: $(LUA_API) gensymbols.sh
	${shell ./gensymbols.sh $(LUA_API) > lunatik_sym.h}

moontastik_install_%:
	[ $* ] || (echo "usage: make moontastik_install_TARGET" ; exit 1)
	wget https://github.com/luainkernel/moontastik/releases/download/${MOONTASTIK_RELEASE}/moontastik_lua.zip -O moontastik_lua.zip
	[ -d moontastik_lua ] && ${RM} -r moontastik_lua || true
	unzip moontastik_lua.zip
	cd moontastik_lua/"$*" && ./install.sh ; cd -

moontastik_uninstall_%:
	[ $* ] || (echo "usage: make moontastik_uninstall_TARGET" ; exit 1)
	${RM} -r ${SCRIPTS_INSTALL_PATH}/$*

doc-site:
	ldoc .

