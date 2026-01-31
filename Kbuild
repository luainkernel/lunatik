# SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
# SPDX-License-Identifier: MIT OR GPL-2.0-only

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

KLIBC_USR := klibc/usr
KLIBC_INC := $(KLIBC_USR)/include/arch/$(KLIBC_ARCH)
KLIBC_LIBGCC := $(KLIBC_USR)/klibc/libgcc

LUNATIK_FLAGS := -D_LUNATIK -D_KERNEL -I${PWD}/$(KLIBC_INC)

asflags-y += $(LUNATIK_FLAGS)
ccflags-y += $(LUNATIK_FLAGS) -DLUNATIK_RUNTIME=$(CONFIG_LUNATIK_RUNTIME) \
	-Wimplicit-fallthrough=0 -I$(src) -I${PWD} -I${PWD}/include -I${PWD}/lua

obj-$(CONFIG_LUNATIK) += lunatik.o

lunatik-objs += lua/lapi.o lua/lcode.o lua/lctype.o lua/ldebug.o lua/ldo.o \
	lua/ldump.o lua/lfunc.o lua/lgc.o lua/llex.o lua/lmem.o \
	lua/lobject.o lua/lopcodes.o lua/lparser.o lua/lstate.o \
	lua/lstring.o lua/ltable.o lua/ltm.o \
	lua/lundump.o lua/lvm.o lua/lzio.o lua/lauxlib.o lua/lbaselib.o \
	lua/lcorolib.o lua/ldblib.o lua/lstrlib.o \
	lua/ltablib.o lua/lutf8lib.o lua/lmathlib.o lua/linit.o \
	lua/loadlib.o $(KLIBC_USR)/klibc/arch/$(KLIBC_ARCH)/setjmp.o \
	lunatik_aux.o lunatik_obj.o lunatik_core.o

ifeq ($(CONFIG_64BIT),)
lunatik-objs += $(KLIBC_LIBGCC)/__udivmoddi4.o	\
	$(KLIBC_LIBGCC)/__divdi3.o $(KLIBC_LIBGCC)/__udivdi3.o \
	$(KLIBC_LIBGCC)/__moddi3.o $(KLIBC_LIBGCC)/__umoddi3.o
endif

obj-$(CONFIG_LUNATIK_RUN) += lunatik_run.o

obj-$(CONFIG_LUNATIK_DEVICE) += lib/lunadevice.o
obj-$(CONFIG_LUNATIK_LINUX) += lib/lunalinux.o
obj-$(CONFIG_LUNATIK_NOTIFIER) += lib/lunanotifier.o
obj-$(CONFIG_LUNATIK_SOCKET) += lib/lunasocket.o
obj-$(CONFIG_LUNATIK_RCU) += lib/lunarcu.o
obj-$(CONFIG_LUNATIK_THREAD) += lib/lunathread.o
obj-$(CONFIG_LUNATIK_FIB) += lib/lunafib.o
obj-$(CONFIG_LUNATIK_DATA) += lib/lunadata.o
obj-$(CONFIG_LUNATIK_PROBE) += lib/lunaprobe.o
obj-$(CONFIG_LUNATIK_SYSCALL) += lib/lunasyscall.o
obj-$(CONFIG_LUNATIK_XDP) += lib/lunaxdp.o
obj-$(CONFIG_LUNATIK_FIFO) += lib/lunafifo.o
obj-$(CONFIG_LUNATIK_XTABLE) += lib/lunaxtable.o
obj-$(CONFIG_LUNATIK_NETFILTER) += lib/lunanetfilter.o
obj-$(CONFIG_LUNATIK_COMPLETION) += lib/lunacompletion.o
obj-$(CONFIG_LUNATIK_CRYPTO_SHASH) += lib/lunacrypto_shash.o
obj-$(CONFIG_LUNATIK_CRYPTO_SKCIPHER) += lib/lunacrypto_skcipher.o
obj-$(CONFIG_LUNATIK_CRYPTO_AEAD) += lib/lunacrypto_aead.o
obj-$(CONFIG_LUNATIK_CRYPTO_RNG) += lib/lunacrypto_rng.o
obj-$(CONFIG_LUNATIK_CRYPTO_COMP) += lib/lunacrypto_comp.o
obj-$(CONFIG_LUNATIK_CPU) += lib/lunacpu.o
obj-$(CONFIG_LUNATIK_HID) += lib/lunahid.o
obj-$(CONFIG_LUNATIK_SIGNAL) += lib/lunasignal.o
obj-$(CONFIG_LUNATIK_BYTEORDER) += lib/lunabyteorder.o

