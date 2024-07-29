# SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only

ifndef LUAXTABLE_MODULE
$(error LUAXTABLE_MODULE is not defined. Run LUAXTABLE_MODULE=<module> make)
endif

CFLAGS = -DLUAXTABLE_MODULE=\"${LUAXTABLE_MODULE}\" -O2 -Wall -I../../../lib
XTABLES_SO_DIR = $(shell pkg-config xtables --variable xtlibdir)
LUA_FLAGS = -llua -lm

all:
	make libxt_${LUAXTABLE_MODULE}.so

install:
	sudo cp libxt_*.so ${XTABLES_SO_DIR}

uninstall:
	sudo rm -f ${XTABLES_SO_DIR}/libxt_${LUAXTABLE_MODULE}.so

clean:
	rm -f libxt_*.so libxt_*.o

lib%.so: lib%.o
	gcc -shared -fPIC -o libxt_${LUAXTABLE_MODULE}.so libxt_${LUAXTABLE_MODULE}.o ${LUA_FLAGS};

lib%.o: luaxt.c
	gcc ${CFLAGS} ${LUA_FLAGS} -D_INIT=lib$*_init -fPIC -c -o libxt_${LUAXTABLE_MODULE}.o $<;

