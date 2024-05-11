MODULES_INSTALL_PATH = /lib/modules/${shell uname -r}
SCRIPTS_INSTALL_PATH = /lib/modules/lua
LUNATIK_INSTALL_PATH = /usr/local/sbin
LUA_API = lua/lua.h lua/lauxlib.h lua/lualib.h
KDIR ?= ${MODULES_INSTALL_PATH}/build

all: lunatik_sym.h
	make -C ${KDIR} M=${PWD} CONFIG_LUNATIK=m	\
	CONFIG_LUNATIK_RUN=m CONFIG_LUNATIK_RUNTIME=y CONFIG_LUNATIK_DEVICE=m	\
	CONFIG_LUNATIK_LINUX=m CONFIG_LUNATIK_NOTIFIER=m CONFIG_LUNATIK_SOCKET=m \
	CONFIG_LUNATIK_RCU=m CONFIG_LUNATIK_THREAD=m CONFIG_LUNATIK_FIB=m \
	CONFIG_LUNATIK_DATA=m CONFIG_LUNATIK_PROBE=m CONFIG_LUNATIK_SYSCALL=m \
	CONFIG_LUNATIK_XDP=m CONFIG_LUNATIK_NETFILTER=m

clean:
	make -C ${KDIR} M=${PWD} clean
	rm lunatik_sym.h

scripts_install:
	mkdir -p -m 0755 ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/socket
	mkdir -p -m 0755 ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/syscall
	install -m 0644 -o root -g root lunatik.lua ${SCRIPTS_INSTALL_PATH}
	install -m 0644 -o root -g root lib/socket/*.lua ${SCRIPTS_INSTALL_PATH}/socket
	install -m 0644 -o root -g root lib/syscall/*.lua ${SCRIPTS_INSTALL_PATH}/syscall
	install -m 0755 -o root -g root lunatik ${LUNATIK_INSTALL_PATH}

scripts_uninstall:
	rm ${SCRIPTS_INSTALL_PATH}/lunatik.lua
	rm -r ${SCRIPTS_INSTALL_PATH}/socket
	rm -r ${SCRIPTS_INSTALL_PATH}/syscall
	rm ${LUNATIK_INSTALL_PATH}/lunatik

examples_install:
	mkdir -p -m 0755 ${SCRIPTS_INSTALL_PATH}/examples
	install -m 0644 -o root -g root examples/*.lua ${SCRIPTS_INSTALL_PATH}/examples
	mkdir -p -m 0755 ${SCRIPTS_INSTALL_PATH}/examples/echod
	install -m 0644 -o root -g root examples/echod/*.lua ${SCRIPTS_INSTALL_PATH}/examples/echod

examples_uninstall:
	rm -r ${SCRIPTS_INSTALL_PATH}/examples

modules_install:
	mkdir -p -m 0755 ${MODULES_INSTALL_PATH}/lunatik
	install -m 0644 -o root -g root *.ko lib/*.ko ${MODULES_INSTALL_PATH}/lunatik

btf_install:
	cp /sys/kernel/btf/vmlinux ${KDIR}

modules_uninstall:
	rm -r ${MODULES_INSTALL_PATH}/lunatik

install: scripts_install modules_install
	depmod -a

uninstall: scripts_uninstall modules_uninstall
	depmod -a

lunatik_sym.h: $(LUA_API)
	${shell ./gensymbols.sh $(LUA_API) > lunatik_sym.h}

