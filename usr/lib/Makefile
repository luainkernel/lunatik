CFLAGS = -O2 -Wall -I../../lib
XTABLES_SO_DIR = $(shell pkg-config xtables --variable xtlibdir)

all:
	make libxt_luaxtabletest.so;

install:
	sudo cp *.so ${XTABLES_SO_DIR}

uninstall:
	sudo rm -f ${XTABLES_SO_DIR}/libxt_luaxtabletest.so

clean:
	rm -f *.o *.so

lib%.so: lib%.o
	gcc -shared -fPIC -o $@ $^;

lib%.o: lib%.c
	gcc ${CFLAGS} -D_INIT=lib$*_init -fPIC -c -o $@ $<;
