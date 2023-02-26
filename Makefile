all: lunatik_sym.h
	make -C /lib/modules/${shell uname -r}/build M=${PWD} \
	CONFIG_LUNATIK=m

clean:
	make -C /lib/modules/${shell uname -r}/build M=${PWD} clean
	rm lunatik_sym.h

api = lua/lua.h lua/lauxlib.h lua/lualib.h
lunatik_sym.h: $(api)
	${shell ./gensymbols.sh $(api) > lunatik_sym.h}

