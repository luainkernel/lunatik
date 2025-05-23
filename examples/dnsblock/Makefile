# SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
# SPDX-License-Identifier: MIT OR GPL-2.0-only

CFLAGS = -O2 -Wall -I../../lib
XTABLES_SO_DIR = $(shell pkg-config xtables --variable xtlibdir)

all:
	make libxt_dnsblock.so;

install:
	sudo cp *.so ${XTABLES_SO_DIR}

uninstall:
	sudo rm -f ${XTABLES_SO_DIR}/libxt_dnsblock.so

clean:
	rm -f *.o *.so

lib%.so: lib%.o
	gcc -shared -fPIC -o $@ $^;

lib%.o: lib%.c
	gcc ${CFLAGS} -D_INIT=lib$*_init -fPIC -c -o $@ $<;

