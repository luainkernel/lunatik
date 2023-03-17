ccflags-y += -D_LUNATIK -D_KERNEL -D_CONFIG_FULL_PANIC -Wimplicit-fallthrough=0 \
	-I$(src) -I${PWD} -I${PWD}/include -I${PWD}/lua
asflags-y += -D_LUNATIK -D_KERNEL

ifeq ($(ARCH), x86)
	ccflags-y += -Dsetjmp=kernel_setjmp -Dlongjmp=kernel_longjmp
	SUB := _$(BITS)
	ifdef CONFIG_X86_32
		asflags-y += -D_REGPARM
	endif
endif

#TODO: we should cleanup this and just define __mips* as CONFIG_MIPS*
ifeq ($(ARCH), mips)
	ifdef CONFIG_64BIT
		ifdef CONFIG_MIPS32_O32
			AFLAGS_setjmp.o += -D__mips_o32
		else
			ifdef CONFIG_MIPS32_N32
				AFLAGS_setjmp.o += -D__mips_n32
			else
				AFLAGS_setjmp.o += -D__mips_n64
			endif
		endif
		AFLAGS_setjmp.o += -D_MIPS_ISA_MIPS64 \
			-D_MIPS_ISA=_MIPS_ISA_MIPS64
        else
		AFLAGS_setjmp.o += -D__mips_o32 -D_MIPS_ISA_MIPS32 \
			-D_MIPS_ISA=_MIPS_ISA_MIPS32
        endif
endif

obj-$(CONFIG_LUNATIK) += lunatik.o

lunatik-objs += lua/lapi.o lua/lcode.o lua/lctype.o lua/ldebug.o lua/ldo.o \
	 lua/ldump.o lua/lfunc.o lua/lgc.o lua/llex.o lua/lmem.o \
	 lua/lobject.o lua/lopcodes.o lua/lparser.o lua/lstate.o \
	 lua/lstring.o lua/ltable.o lua/ltm.o \
	 lua/lundump.o lua/lvm.o lua/lzio.o lua/lauxlib.o lua/lbaselib.o \
	 lua/lcorolib.o lua/ldblib.o lua/lstrlib.o \
	 lua/ltablib.o lua/lutf8lib.o lua/lmathlib.o lua/linit.o \
	 lua/loadlib.o arch/$(ARCH)/setjmp$(SUB).o lunatik_aux.o lunatik_core.o

obj-$(CONFIG_LUNATIK_RUN) += lunatik_run.o

obj-$(CONFIG_LUNATIK_DEVICE) += lib/luadevice.o
obj-$(CONFIG_LUNATIK_LINUX) += lib/lualinux.o

