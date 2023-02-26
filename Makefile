all: lunatik_sym.h
	make -C /lib/modules/${shell uname -r}/build M=${PWD} \
	CONFIG_LUNATIK=m

clean:
	make -C /lib/modules/${shell uname -r}/build M=${PWD} clean
	rm lunatik_sym.h

lunatik_sym.h: lua/lua.h lua/lauxlib.h lua/lualib.h
	cat lua/lua.h lua/lauxlib.h lua/lualib.h | sed "s/.*luaconf.h.*//g" | \
	cpp -Ilua/ -D_KERNEL -E -pipe | grep API | \
	sed "s/.*(\(\w*\))\s*(.*/EXPORT_SYMBOL(\1);/g" > lunatik_sym.h

