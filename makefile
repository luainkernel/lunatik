# $Id: makefile,v 1.30 1997/03/31 14:17:09 roberto Exp roberto $

#configuration

# define (undefine) POPEN if your system (does not) support piped I/O
# define (undefine) _POSIX_SOURCE if your system is (not) POSIX compliant
#define (undefine) NOSTRERROR if your system does NOT have function "strerror"
# (although this is ANSI, SunOS does not comply; so, add "-DNOSTRERROR" on SunOS)
CONFIG = -DPOPEN -D_POSIX_SOURCE
# Compilation parameters
CC = gcc
CFLAGS = $(CONFIG) -Wall -Wmissing-prototypes -Wshadow -ansi -O2 -pedantic

#CC = acc
#CFLAGS = -fast -I/usr/5include

AR = ar
ARFLAGS	= rvl


# Aplication modules
LUAOBJS = \
	parser.o \
	lex.o \
	opcode.o \
	hash.o \
	table.o \
	inout.o \
	tree.o \
	fallback.o \
	luamem.o \
	func.o \
	undump.o \
	auxlib.o

LIBOBJS = 	\
	iolib.o \
	mathlib.o \
	strlib.o


lua : lua.o liblua.a liblualib.a
	$(CC) $(CFLAGS) -o $@ lua.o -L. -llua -llualib -lm

liblua.a : $(LUAOBJS)
	$(AR) $(ARFLAGS) $@  $?
	ranlib $@

liblualib.a : $(LIBOBJS)
	$(AR) $(ARFLAGS) $@  $?
	ranlib $@

liblua.so.1.0 : lua.o
	ld -o liblua.so.1.0 $(LUAOBJS)

y.tab.c y.tab.h  : lua.stx
	yacc -d lua.stx

parser.c : y.tab.c
	sed -e 's/yy/luaY_/g' -e 's/malloc\.h/stdlib\.h/g' y.tab.c > parser.c

parser.h : y.tab.h
	sed -e 's/yy/luaY_/g' y.tab.h > parser.h

clear	:
	rcsclean
	rm -f *.o
	rm -f parser.c parser.h y.tab.c y.tab.h
	co lua.h lualib.h luadebug.h


%.h : RCS/%.h,v
	co $@

%.c : RCS/%.c,v
	co $@


auxlib.o: auxlib.c lua.h auxlib.h
fallback.o: fallback.c auxlib.h lua.h luamem.h fallback.h opcode.h \
 types.h tree.h func.h table.h hash.h
func.o: func.c luadebug.h lua.h table.h tree.h types.h opcode.h func.h \
 luamem.h
hash.o: hash.c luamem.h opcode.h lua.h types.h tree.h func.h hash.h \
 table.h
inout.o: inout.c auxlib.h lua.h lex.h opcode.h types.h tree.h func.h \
 inout.h table.h hash.h luamem.h fallback.h
iolib.o: iolib.c lua.h auxlib.h luadebug.h lualib.h
lex.o: lex.c auxlib.h lua.h luamem.h tree.h types.h table.h opcode.h \
 func.h lex.h inout.h luadebug.h parser.h
lua.o: lua.c lua.h lualib.h
luamem.o: luamem.c luamem.h lua.h
mathlib.o: mathlib.c lualib.h lua.h auxlib.h
opcode.o: opcode.c luadebug.h lua.h luamem.h opcode.h types.h tree.h \
 func.h hash.h inout.h table.h fallback.h undump.h
parser.o: parser.c luadebug.h lua.h luamem.h lex.h opcode.h types.h \
 tree.h func.h hash.h inout.h table.h
strlib.o: strlib.c lua.h auxlib.h lualib.h
table.o: table.c luamem.h opcode.h lua.h types.h tree.h func.h hash.h \
 table.h inout.h fallback.h luadebug.h
tree.o: tree.c luamem.h lua.h tree.h types.h lex.h hash.h opcode.h \
 func.h table.h fallback.h
undump.o: undump.c opcode.h lua.h types.h tree.h func.h luamem.h \
 table.h undump.h
