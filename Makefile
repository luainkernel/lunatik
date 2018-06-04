subdir-ccflags-y := -D_KERNEL -I$(src)

obj-$(CONFIG_LUNATIK) +=lunatik.o

lunatik-objs := lua/lapi.o lua/lcode.o lua/lctype.o lua/ldebug.o lua/ldo.o \
         lua/ldump.o lua/lfunc.o lua/lgc.o lua/llex.o lua/lmem.o \
	 lua/lobject.o lua/lopcodes.o lua/lparser.o lua/lstate.o \
         lua/lstring.o lua/ltable.o lua/ltm.o \
	 lua/lundump.o lua/lvm.o lua/lzio.o lua/lauxlib.o lua/lbaselib.o \
         lua/lbitlib.o lua/lcorolib.o lua/ldblib.o lua/lstrlib.o \
	 lua/ltablib.o lua/lutf8lib.o lua/loslib.o lua/lmathlib.o lua/linit.o

lunatik-objs += arch/$(ARCH)/setjmp.o

lunatik-objs += socket/socket.o socket/enums.o

subdir-ccflags-${CONFIG_LUNATIK_DATA} += -I$(src)/luadata -I$(src)/lua -D'CHAR_BIT=(8)' \
	-D'MIN=min' -D'MAX=max' -D'UCHAR_MAX=(255)' -D'UINT64_MAX=(U64_MAX)' -DLUANTICK_DATA

lunatik-${CONFIG_LUNATIK_DATA} += luadata/binary.o luadata/data.o luadata/handle.o \
	luadata/layout.o luadata/luadata.o luadata/luautil.o

lunatik-${CONFIG_LUNATIK_POC} += poc-driver/luadrv.o