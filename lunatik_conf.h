/*
* SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#ifndef lunatik_conf_h
#define lunatik_conf_h

typedef struct lua_State lua_State;

#undef LUA_INTEGER
#undef LUA_INTEGER_FRMLEN
#undef LUA_UNSIGNED
#undef LUA_MAXUNSIGNED
#undef LUA_MAXINTEGER
#undef LUA_MININTEGER

#define LUA_INTEGER		long long
#define LUA_INTEGER_FRMLEN	"ll"
#define LUA_UNSIGNED	        unsigned long long
#define LUA_MAXUNSIGNED		ULLONG_MAX
#define LUA_MAXINTEGER		LLONG_MAX
#define LUA_MININTEGER		LLONG_MIN

#define LUAI_UACNUMBER		LUA_INTEGER
#define LUA_NUMBER		LUA_INTEGER
#define LUA_NUMBER_FMT		LUA_INTEGER_FMT

#if BITS_PER_LONG == 64
#define lunatik_idiv(L, m, n)	((m) / (n))
#define lunatik_uidiv(L, m, n)	((m) / (n))
#define lunatik_imod(L, m, n)	((m) % (n))
#define lunatik_hashmod(t, n)	hashmod((t), (n))
#elif BITS_PER_LONG == 32
#include <linux/bug.h>
#include <linux/math64.h>
static inline LUA_UNSIGNED _lunatik_uimod(LUA_UNSIGNED m, LUA_UNSIGNED n)
{
	u64 r;
	//BUG_ON(n > ULONG_MAX);
	div64_u64_rem(m, n, &r);
	return r;
}
#define lunatik_hashmod(t, n)	(gnode(t, _lunatik_uimod((n), ((sizenode(t)-1)|1))))

int (luaL_error) (lua_State *L, const char *fmt, ...);

#define lunatik_checklong(L, n, s)			\
do {							\
	if (unlikely(n < LONG_MIN || n > LONG_MAX))	\
		luaL_error(L, s);			\
} while(0)

#define lunatik_checkulong(L, n, s)	\
do {					\
	if (unlikely(n > ULONG_MAX))	\
		luaL_error(L, s);	\
} while(0)

static inline LUA_INTEGER lunatik_idiv(lua_State *L, LUA_INTEGER m, LUA_INTEGER n)
{
	lunatik_checklong(L, n, "attempt to divide by a 64-bit value");
	return div64_s64(m, n);
}

static inline LUA_UNSIGNED lunatik_uidiv(lua_State *L, LUA_UNSIGNED m, LUA_UNSIGNED n)
{
	lunatik_checkulong(L, n, "attempt to divide by a 64-bit value");
	return div64_u64(m, n);
}

static inline LUA_INTEGER lunatik_imod(lua_State *L, LUA_INTEGER m, LUA_INTEGER n)
{
	s32 r;
	lunatik_checklong(L, n, "attempt to perform 'n%%' with a 64-bit value");
	div_s64_rem(m, (s32)n, &r);
	return (LUA_INTEGER)r;
}
#else /* BITS_PER_LONG */
#error unsuported platform
#endif /* BITS_PER_LONG */

#define l_randomizePivot()	(~0)

#include <linux/random.h>
#define luai_makeseed(L)		get_random_u32()

#define lua_writestring(s,l)		printk("%s",(s))
#define lua_writeline()			pr_cont("\n")
#define lua_writestringerror(...)	pr_err(__VA_ARGS__)

/* see https://www.gnu.org/software/libc/manual/html_node/Atomic-Types.html */
#define l_signalT	int

/* frame size shouldn't be larger than 1024 bytes; thus, LUAL_BUFFERSIZE
 * must be adjusted for the stack of functions that use luaL_Buffer */
#undef LUAL_BUFFERSIZE
#define LUAL_BUFFERSIZE		(256) /* {laux,load,lstr,ltab,lutf8}lib.c */

#ifdef lauxlib_c
#define panic	lua_panic
#endif

#include <linux/module.h>
#ifdef MODULE /* see https://lwn.net/Articles/813350/ */
void *lunatik_lookup(const char *symbol);
#define lsys_loadlib(l)		__symbol_get((l))
#define lsys_unloadlib(l)	symbol_put_addr((l))
#else
#include <linux/kallsyms.h>
#define lunatik_lookup(s)	((void *)kallsyms_lookup_name((l)))
#define lsys_loadlib(l)		lunatik_lookup(l)
#define lsys_unloadlib(l)
#endif

#define lsys_sym(L,l,s)		((lua_CFunction)(l))

const char *lua_pushfstring(lua_State *L, const char *fmt, ...);

static inline void *lsys_load(lua_State *L, const char *symbol, int seeglb)
{
	void *lib;
	(void)(seeglb); /* not used */
	if ((lib = lsys_loadlib(symbol)) == NULL)
		lua_pushfstring(L, "%s not found in kernel symbol table", symbol);
	return lib;
}

int lunatik_loadfile(lua_State *L, const char *filename, const char *mode);
#define luaL_loadfilex(L,f,m)	lunatik_loadfile((L),(f),(m))

#undef LUA_ROOT
#define LUA_ROOT	"/lib/modules/lua/"

#undef LUA_PATH_DEFAULT
#define LUA_PATH_DEFAULT  LUA_ROOT"?.lua;" LUA_ROOT"?/init.lua"

#undef LUAI_MAXSTACK
#define LUAI_MAXSTACK  200

#if defined(lcode_c) || defined(ldebug_c) || defined(llex_c) || defined(lparser_c) || defined(lstate_c)
#ifdef current /* defined by asm/current.h */
#undef current /* conflicts with Lua namespace */
#endif
#endif

#endif

