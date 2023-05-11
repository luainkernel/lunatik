MODULES_INSTALL_PATH = /lib/modules/${shell uname -r}
SCRIPTS_INSTALL_PATH = /lib/modules/lua
LUNATIK_INSTALL_PATH = /usr/local/sbin
LUA_API = lua/lua.h lua/lauxlib.h lua/lualib.h

all: lunatik_sym.h
	make -C ${MODULES_INSTALL_PATH}/build M=${PWD} CONFIG_LUNATIK=m	\
	CONFIG_LUNATIK_RUN=m CONFIG_LUNATIK_RUNTIME=y CONFIG_LUNATIK_DEVICE=m	\
	CONFIG_LUNATIK_LINUX=m CONFIG_LUNATIK_NOTIFIER=m CONFIG_LUNATIK_SOCKET=m

clean:
	make -C ${MODULES_INSTALL_PATH}/build M=${PWD} clean
	rm lunatik_sym.h

scripts_install:
	mkdir -p -m 0755 ${SCRIPTS_INSTALL_PATH} ${SCRIPTS_INSTALL_PATH}/socket
	install -m 0644 -o root -g root lunatik.lua ${SCRIPTS_INSTALL_PATH}
	install -m 0644 -o root -g root lib/socket/*.lua ${SCRIPTS_INSTALL_PATH}/socket
	install -m 0755 -o root -g root lunatik ${LUNATIK_INSTALL_PATH}

scripts_uninstall:
	rm ${SCRIPTS_INSTALL_PATH}/lunatik.lua
	rm -r ${SCRIPTS_INSTALL_PATH}/socket
	rm ${LUNATIK_INSTALL_PATH}/lunatik

examples_install:
	mkdir -p -m 0755 ${SCRIPTS_INSTALL_PATH}/examples
	install -m 0644 -o root -g root examples/*.lua ${SCRIPTS_INSTALL_PATH}/examples

examples_uninstall:
	rm -r ${SCRIPTS_INSTALL_PATH}/examples

modules_install:
	mkdir -p -m 0755 ${MODULES_INSTALL_PATH}/lunatik
	install -m 0644 -o root -g root *.ko lib/*.ko ${MODULES_INSTALL_PATH}/lunatik

modules_uninstall:
	rm -r ${MODULES_INSTALL_PATH}/lunatik

install: scripts_install modules_install
	depmod -a

uninstall: scripts_uninstall modules_uninstall
	depmod -a

lunatik_sym.h: $(LUA_API)
	${shell ./gensymbols.sh $(LUA_API) > lunatik_sym.h}

