ifeq ($(ARCH), x86)
	ifdef CONFIG_X86_32
		KLIBC_ARCH := i386
		asflags-y += -D_REGPARM
	else
		KLIBC_ARCH := x86_64
	endif
else
	KLIBC_ARCH := $(ARCH)
endif

KLIBC_USR := /klibc/usr
#CFLAGS_lunatik.o = -D_LUNATIK -D_KERNEL -DLUNATIK_RUNTIME=$(CONFIG_LUNATIK_RUNTIME) \
ccflags-y += -D_LUNATIK -D_KERNEL -DLUNATIK_RUNTIME=$(CONFIG_LUNATIK_RUNTIME) \
	-Wimplicit-fallthrough=0 -I$(src) -I${PWD} -I${PWD}/include -I${PWD}/lua \
	-I${PWD}$(KLIBC_USR)/include/arch/$(KLIBC_ARCH)

obj-m += lunatik.o

setjmp.o: setjmp.S
        $(AS) $(ASFLAGS) -o setjmp.o setjmp.S

lunatik-objs += lua/lapi.o lua/lcode.o lua/lctype.o lua/ldebug.o lua/ldo.o \
	lua/ldump.o lua/lfunc.o lua/lgc.o lua/llex.o lua/lmem.o \
	lua/lobject.o lua/lopcodes.o lua/lparser.o lua/lstate.o \
	lua/lstring.o lua/ltable.o lua/ltm.o \
	lua/lundump.o lua/lvm.o lua/lzio.o lua/lauxlib.o lua/lbaselib.o \
	lua/lcorolib.o lua/ldblib.o lua/lstrlib.o \
	lua/ltablib.o lua/lutf8lib.o lua/lmathlib.o lua/linit.o \
	lua/loadlib.o setjmp.o \
	lunatik_aux.o lunatik_obj.o lunatik_core.o

obj-m += lunatik_run.o

obj-m += lib/luadevice.o
obj-m += lib/lualinux.o
obj-m += lib/luanotifier.o
obj-m += lib/luasocket.o
obj-m += lib/luarcu.o
obj-m += lib/luathread.o
obj-m += lib/luafib.o
obj-m += lib/luadata.o
obj-m += lib/luaprobe.o
obj-m += lib/luasyscall.o
#obj-m += lib/luaxdp.o
obj-m += lib/luafifo.o
#obj-m += lib/luaxtable.o
obj-m += lib/luanetfilter.o
obj-m += lib/luacompletion.o

