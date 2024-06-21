MODULES_INSTALL_PATH = /lib/modules/${shell uname -r}
SCRIPTS_INSTALL_PATH = /lib/modules/lua
LUNATIK_INSTALL_PATH = /usr/local/sbin
LUA_API = lua/lua.h lua/lauxlib.h lua/lualib.h
KDIR ?= ${MODULES_INSTALL_PATH}/build
RM = rm -f
MKDIR = mkdir -p -m 0755
INSTALL = install -o root -g root

all: lunatik_sym.h
	make -C ${KDIR} M=${PWD} CONFIG_LUNATIK=m	\
	CONFIG_LUNATIK_RUN=m CONFIG_LUNATIK_RUNTIME=y CONFIG_LUNATIK_DEVICE=m	\
	CONFIG_LUNATIK_LINUX=m CONFIG_LUNATIK_NOTIFIER=m CONFIG_LUNATIK_SOCKET=m \
	CONFIG_LUNATIK_RCU=m CONFIG_LUNATIK_THREAD=m CONFIG_LUNATIK_FIB=m \
	CONFIG_LUNATIK_DATA=m CONFIG_LUNATIK_PROBE=m CONFIG_LUNATIK_SYSCALL=m \
	CONFIG_LUNATIK_XDP=m CONFIG_LUNATIK_FIFO=m

clean:
	make -C ${KDIR} M=${PWD} clean
	${RM} lunatik_sym.h

scripts_install:
	${MKDIR} ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/socket
	${MKDIR} ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/syscall
	${INSTALL} -m 0644 driver.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/mailbox.lua ${SCRIPTS_INSTALL_PATH}/
	${INSTALL} -m 0644 lib/socket/*.lua ${SCRIPTS_INSTALL_PATH}/socket
	${INSTALL} -m 0644 lib/syscall/*.lua ${SCRIPTS_INSTALL_PATH}/syscall
	${INSTALL} -m 0755 bin/lunatik ${LUNATIK_INSTALL_PATH}

scripts_uninstall:
	${RM} ${SCRIPTS_INSTALL_PATH}/driver.lua
	${RM} ${SCRIPTS_INSTALL_PATH}/mailbox.lua
	${RM} -r ${SCRIPTS_INSTALL_PATH}/socket
	${RM} -r ${SCRIPTS_INSTALL_PATH}/syscall
	${RM} ${LUNATIK_INSTALL_PATH}/lunatik

examples_install:
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/examples
	${INSTALL} -m 0644 examples/*.lua ${SCRIPTS_INSTALL_PATH}/examples
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/examples/echod
	${INSTALL} -m 0644 examples/echod/*.lua ${SCRIPTS_INSTALL_PATH}/examples/echod
	${MKDIR} ${SCRIPTS_INSTALL_PATH}/examples/filter
	${INSTALL} -m 0644 examples/filter/*.lua ${SCRIPTS_INSTALL_PATH}/examples/filter

examples_uninstall:
	${RM} -r ${SCRIPTS_INSTALL_PATH}/examples

modules_install:
	${MKDIR} ${MODULES_INSTALL_PATH}/lunatik
	${INSTALL} -m 0644 *.ko lib/*.ko ${MODULES_INSTALL_PATH}/lunatik

btf_install:
	cp /sys/kernel/btf/vmlinux ${KDIR}

modules_uninstall:
	${RM} -r ${MODULES_INSTALL_PATH}/lunatik

install: scripts_install modules_install
	depmod -a

uninstall: scripts_uninstall modules_uninstall
	depmod -a

lunatik_sym.h: $(LUA_API)
	${shell ./gensymbols.sh $(LUA_API) > lunatik_sym.h}

