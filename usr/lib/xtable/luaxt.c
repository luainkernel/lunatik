/*
* SPDX-FileCopyrightText: (c) 2024 Mohammad Shehar Yaar Tausif <sheharyaar48@gmail.com>
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>

#include <errno.h>
#include <xtables.h>

#include "luaxtable.h"

#ifndef LUAXTABLE_MODULE
#error "LUAXTABLE_MODULE is not defined"
#endif

#define pr_err(fmt, ...) fprintf(stderr, fmt, ##__VA_ARGS__)
#define MIN(a,b) (((a)<(b))?(a):(b))

typedef struct luaxt_flags_s {
	const char *name;
	lua_Integer value;
} luaxt_flags_t;

static lua_State *L = NULL;
static int luaopen_luaxt(lua_State *L);
static int luaxt_match(lua_State *L);
static int luaxt_target(lua_State *L);

static int luaxt_run(lua_State *L, const char *func_name, const char *key, int nargs, int nresults)
{
	int ret = -1;
	int base = lua_gettop(L) - nargs;
	lua_rawgetp(L, LUA_REGISTRYINDEX, key);

	if (lua_getfield(L, -1, func_name) != LUA_TFUNCTION) {
		pr_err("Function %s not found\n", func_name);
		goto restore;
	}

	lua_insert(L, base + 1); /* func */
	lua_pop(L, 1); /* table */

	if (lua_pcall(L, nargs, nresults, 0) != LUA_OK) {
		pr_err("Failed to call Lua function %s: %s\n", func_name,
				lua_tostring(L, -1));
		goto restore;
	}

	if (nresults == 1)
		ret = lua_toboolean(L, -1);
restore:
	lua_settop(L, base);
	return ret;
}

static int luaxt_doparams(lua_State *L, const char *op, const char *key, unsigned int *flags, luaxtable_info_t *info)
{
	int ret;
	lua_newtable(L);
	lua_pushvalue(L, -1); /* stack : param param */

	ret = luaxt_run(L, op, key, 1, 1);
	if (ret == -1)
		return 0;

	if (flags && (lua_getfield(L, -1, "flags") == LUA_TNUMBER)) {
		*flags = lua_tointeger(L, -1);
		lua_pop(L, 1);
	}

	if (lua_getfield(L, -1, "userdata") == LUA_TSTRING) {
		size_t len = 0;
		const char *ldata = lua_tolstring(L, -1, &len);
		memset(info->userdata, 0, 256);
		memcpy(info->userdata, ldata, MIN(len, 256));
		lua_pop(L, 1);
	}
		
	lua_pop(L, 1);
	return ret;
}

#define LUAXT_HELPER_CB(hook)			   	\
static void luaxt_##hook##_help(void)		   	\
{							   	\
	luaxt_run(L, "help", (void *)luaxt_##hook, 0, 0);	\
}

#define LUAXT_INITER_CB(hook)				   	\
static void luaxt_##hook##_init(struct xt_entry_##hook *hook)   	\
{								   	\
	luaxt_doparams(L, "init", (void *)luaxt_##hook, NULL, (luaxtable_info_t *)(hook->data));	\
}

#define LUAXT_PARSER_CB(hook)			   		\
static int luaxt_##hook##_parse(int c, char **argv, int invert, unsigned int *flags,	\
					const void *entry, struct xt_entry_##hook **hook)	\
{							   		\
	return luaxt_doparams(L, "parse", (void *)luaxt_##hook, flags, (luaxtable_info_t *)((*hook)->data));	\
}

#define LUAXT_FINALCHECKER_CB(hook)				\
static void luaxt_##hook##_finalcheck(unsigned int flags)		\
{							  		\
	lua_pushnumber(L, flags);					\
	luaxt_run(L, "final_check", (void *)luaxt_##hook, 1, 0);	\
}

#define LUAXT_PRINTER_CB(hook)  					\
static void luaxt_##hook##_print(const void *entry, const struct xt_entry_##hook *hook, int numeric)	\
{							   		\
	luaxtable_info_t *info = (luaxtable_info_t *)hook->data;	\
	lua_pushstring(L, info->userdata);				\
	luaxt_run(L, "print", (void *)luaxt_##hook, 1, 0);		\
}

#define LUAXT_SAVER_CB(hook)				\
static void luaxt_##hook##_save(const void *entry, const struct xt_entry_##hook *hook)  \
{									\
	luaxtable_info_t *info = (luaxtable_info_t *)hook->data;	\
	lua_pushstring(L, info->userdata);				\
	luaxt_run(L, "save", (void *)luaxt_##hook, 1, 0);		\
}

#define LUAXT_NEWCB(hook)  		\
	LUAXT_HELPER_CB(hook)   	\
	LUAXT_INITER_CB(hook)   	\
	LUAXT_PARSER_CB(hook)   	\
	LUAXT_FINALCHECKER_CB(hook)	\
	LUAXT_PRINTER_CB(hook)  	\
	LUAXT_SAVER_CB(hook)

LUAXT_NEWCB(match);
LUAXT_NEWCB(target);

#define LUAXT_NEWREG(hook)					\
static struct xtables_##hook luaxt_##hook##_reg = {		\
	.version = XTABLES_VERSION,				\
	.name = LUAXTABLE_MODULE,					\
	.size = XT_ALIGN(sizeof(luaxtable_info_t)),		\
	.userspacesize = 0,					\
	.help = luaxt_##hook##_help,			\
	.init = luaxt_##hook##_init,			\
	.parse = luaxt_##hook##_parse,		 	\
	.final_check = luaxt_##hook##_finalcheck,	  	\
	.print = luaxt_##hook##_print,		  	\
	.save = luaxt_##hook##_save			 	\
}

LUAXT_NEWREG(match);
LUAXT_NEWREG(target);

static inline int luaxt_checkint(lua_State *L, int idx, const char *key)
{
	if (lua_getfield(L, idx, key) != LUA_TNUMBER) {
		pr_err("invalid \'%s\' in ops\n", key);
		return 0;
	}
	int ret = lua_tointeger(L, -1);
	lua_pop(L, 1);
	return ret;
}

#define LUAXT_LIB_CB(hook)				\
static int luaxt_##hook(lua_State *L)		\
{							\
	luaL_checktype(L, 1, LUA_TTABLE);		\
							\
	luaxt_##hook##_reg.revision = luaxt_checkint(L, 1, "revision");		\
	luaxt_##hook##_reg.family = luaxt_checkint(L, 1, "family");		\
	xtables_register_##hook(&luaxt_##hook##_reg);		\
	lua_pushvalue(L, 1);						\
	lua_rawsetp(L, LUA_REGISTRYINDEX, luaxt_##hook);		\
	return 0;							\
}

LUAXT_LIB_CB(match);
LUAXT_LIB_CB(target);

static const luaL_Reg luaxt_lib[] = {
	{"match", luaxt_match},
	{"target", luaxt_target},
	{NULL, NULL}
};

static const luaxt_flags_t luaxt_family[] = {
	{"UNSPEC", NFPROTO_UNSPEC},
	{"INET", NFPROTO_INET},
	{"IPV4", NFPROTO_IPV4},
	{"IPV6", NFPROTO_IPV6},
	{"ARP", NFPROTO_ARP},
	{"NETDEV", NFPROTO_NETDEV},
	{"BRIDGE", NFPROTO_BRIDGE},
	{NULL, 0}
};

static int luaopen_luaxt(lua_State *L)
{
	const luaxt_flags_t *flag;
	luaL_newlib(L, luaxt_lib);
	lua_newtable(L);
	for (flag = luaxt_family; flag->name; flag++) {
		lua_pushinteger(L, flag->value);
		lua_setfield(L, -2, flag->name); /* namespace[name] = value */
	}
	lua_setfield(L, -2, "family"); /* lib.namespace = namespace */
	return 1;
}

static int __attribute__((constructor)) _init(void)
{
	if ((L = luaL_newstate()) == NULL) {
		pr_err("Failed to create Lua state\n");
		return -ENOMEM;
	}
	luaL_openlibs(L);
	luaL_requiref(L, "luaxt", luaopen_luaxt, 1);

	if (luaL_dofile(L, "libxt_"LUAXTABLE_MODULE".lua") != LUA_OK) {
		pr_err("Failed to load Lua script: %s\n", lua_tostring(L, -1));
		return -ENOENT;
	}
	return 0;
}

static void __attribute__((destructor)) _fini(void)
{
	if (L != NULL)
		lua_close(L);
}

