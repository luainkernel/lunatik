# SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

KERNEL_RELEASE ?= ${shell uname -r}
MODULES_PATH := /lib/modules
MODULES_RELEASE_PATH := ${MODULES_PATH}/${KERNEL_RELEASE}
# needed when zfs module is installed
MODULES_ORDER_LIST := kernel/zfs/zfs.ko kernel/zfs/zlua.ko updates/dkms/zfs.ko updates/dkms/zlua.ko
MODULES_ORDER_FILE := ${MODULES_RELEASE_PATH}/modules.order
BTF_INSTALL_PATH = ${MODULES_RELEASE_PATH}/build
MODULES_BUILD_PATH ?= ${BTF_INSTALL_PATH}
MODULES_INSTALL_PATH := ${MODULES_RELEASE_PATH}/kernel
SCRIPTS_INSTALL_PATH := ${MODULES_PATH}/lua
INCLUDE_PATH := ${MODULES_BUILD_PATH}/include

LUA ?= lua5.4
LUA_PATH ?= $(shell $(LUA) -e 'print(package.path:match("([^;]*)/%?%.lua;"))')

LUNATIK_INSTALL_PATH = /usr/local/sbin
LUNATIK_EBPF_INSTALL_PATH = /usr/local/lib/bpf/lunatik
MOONTASTIK_RELEASE ?= v0.1c
LUA_API = lua/lua.h lua/lauxlib.h lua/lualib.h
RM = rm -f
MKDIR = mkdir -p -m 0755
LN = ln -sf
INSTALL = install -o root -g root

CONFIG_LUNATIK ?= m
CONFIG_LUNATIK_RUNTIME ?= y
CONFIG_LUNATIK_RUN ?= m

LUNATIK_MODULES := DEVICE LINUX NOTIFIER SOCKET RCU THREAD FIB DATA PROBE SYSCALL XDP FIFO XTABLE NETFILTER \
	COMPLETION CRYPTO_SHASH CRYPTO_SKCIPHER CRYPTO_AEAD CRYPTO_RNG CRYPTO_COMP CPU HID SIGNAL BYTEORDER

$(foreach c,$(LUNATIK_MODULES),\
	$(eval CONFIG_LUNATIK_$(c) ?= m))

# disable modules here, e.g.:
# CONFIG_LUNATIK_SYSCALL := n

LUNATIK_CONFIG_MODULES := \
	$(foreach c,$(LUNATIK_MODULES),CONFIG_LUNATIK_$(c)=$(CONFIG_LUNATIK_$(c)))

LUNATIK_CONFIG_FLAGS := CONFIG_LUNATIK=$(CONFIG_LUNATIK) CONFIG_LUNATIK_RUNTIME=$(CONFIG_LUNATIK_RUNTIME) \
	CONFIG_LUNATIK_RUN=$(CONFIG_LUNATIK_RUN) $(LUNATIK_CONFIG_MODULES)

LUNATIK_MODULES := \
	$(foreach c,$(LUNATIK_MODULES),\
		$(if $(filter y m,$(CONFIG_LUNATIK_$(c))),$(c)))

all: lunatik_sym.h configure
	${MAKE} -C ${MODULES_BUILD_PATH} M=${PWD} $(LUNATIK_CONFIG_FLAGS)

clean:
	${MAKE} -C ${MODULES_BUILD_PATH} M=${PWD} clean
	${MAKE} -C examples/filter clean
	${RM} lunatik_sym.h
	${RM} autogen/lunatik/*.lua
	${RM} autogen/linux/*.lua

scripts_install:
	${MKDIR} ${SCRIPTS_INSTALL_PATH}
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/lunatik
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/socket
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/syscall
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/crypto
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/linux
	${MKDIR} ${LUA_PATH}/lunatik
	${INSTALL} -m 0644 driver.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/mailbox.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/net.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/util.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/lunatik/*.lua ${SCRIPTS_INSTALL_PATH}/lunatik
	${INSTALL} -m 0644 lib/socket/*.lua ${SCRIPTS_INSTALL_PATH}/socket
	${INSTALL} -m 0644 lib/syscall/*.lua ${SCRIPTS_INSTALL_PATH}/syscall
	${INSTALL} -m 0644 lib/crypto/*.lua ${SCRIPTS_INSTALL_PATH}/crypto
	${INSTALL} -m 0644 autogen/linux/*.lua ${SCRIPTS_INSTALL_PATH}/linux
	${INSTALL} -m 0644 autogen/lunatik/*.lua ${SCRIPTS_INSTALL_PATH}/lunatik
	${LN} ${SCRIPTS_INSTALL_PATH}/lunatik/config.lua ${LUA_PATH}/lunatik/config.lua
	${INSTALL} -D -m 0755 bin/lunatik ${LUNATIK_INSTALL_PATH}/lunatik

scripts_uninstall:
	${RM} ${SCRIPTS_INSTALL_PATH}/driver.lua
	${RM} ${SCRIPTS_INSTALL_PATH}/runner.lua
	${RM} ${SCRIPTS_INSTALL_PATH}/mailbox.lua
	${RM} ${SCRIPTS_INSTALL_PATH}/net.lua
	${RM} -r ${SCRIPTS_INSTALL_PATH}/lunatik
	${RM} -r ${SCRIPTS_INSTALL_PATH}/socket
	${RM} -r ${SCRIPTS_INSTALL_PATH}/syscall
	${RM} -r ${SCRIPTS_INSTALL_PATH}/crypto
	${RM} -r ${SCRIPTS_INSTALL_PATH}/linux
	${RM} ${LUNATIK_INSTALL_PATH}/lunatik
	${RM} -r ${LUA_PATH}/lunatik

.PHONY: ebpf defines
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
	${shell CC='$(CC)' ./gensymbols.sh $(LUA_API) > lunatik_sym.h}

configure:
	CC='$(CC)' "$(LUA)" configure.lua "$(KERNEL_RELEASE)" "$(INCLUDE_PATH)" "$(LUNATIK_MODULES)"

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

