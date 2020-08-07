/*
 * Copyright (c) 2020 Matheus Rodrigues <matheussr61@gmail.com>
 * Copyright (C) 2017-2019  CUJO LLC
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <stdbool.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include <lauxlib.h>
#include <lua.h>
#include <lmemlib.h>

#include "lunatik.h"

#ifndef _UNUSED
extern int luaopen_memory(lua_State *L);
#endif /*_UNUSED*/

#define DEFAULT_MAXALLOC_BYTES	(32 * 1024)

static int pusherrmsg(lua_State *L, const char *msg)
{
	lua_pushnil(L);
	lua_pushstring(L, msg);
	return 2;
}

static int pusherrno(lua_State *L, int err)
{
	int r = pusherrmsg(L, strerror(-err));
	lua_pushinteger(L, err);
	return r + 1;
}

#ifndef _UNUSED
static int pushioresult(lua_State *L, int code)
{
	if (code >= 0) {
		lua_pushboolean(L, true);
		return 1;
	}
	return pusherrno(L, code);
}
#endif

static void newclass(lua_State *L, const char *name,
				const luaL_Reg mt[])
{
	luaL_newmetatable(L, name);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	luaL_setfuncs(L, mt, 0);
	lua_pop(L, 1);
}

static int lsession_open(lua_State *L)
{
	int ret;
	struct lunatik_session *session = lua_newuserdata(L, sizeof(struct lunatik_session));

	luaL_setmetatable(L, "lunatik.session");
	ret = lunatikS_init(session);

	return ret < 0 ? pusherrno(L, ret) : 1;
}

static int lsession_gc(lua_State *L)
{
	struct lunatik_session *session = luaL_checkudata(L, 1, "lunatik.session");
	if (lunatikS_isopen(session)) lunatikS_close(session);
	return 0;
}

static struct lunatik_session *getsession(lua_State *L)
{
	struct lunatik_session *c = luaL_checkudata(L, 1, "lunatik.session");
	if (!lunatikS_isopen(c))
		luaL_argerror(L, 1, "socket closed");
	return c;
}

static struct lunatik_nl_state *getnlstate(lua_State *L)
{
	struct lunatik_nl_state *s = luaL_checkudata(L, 1, "states.control");
	if (s == NULL)
		luaL_argerror(L, 1, "Failed to get state");
	return s;
}

static int lsession_close(lua_State *L)
{
	struct lunatik_session *session = getsession(L);
	lunatikS_close(session);
	lua_pushboolean(L, true);
	return 1;
}

static int lsession_getfd(lua_State *L)
{
	struct lunatik_session *session = getsession(L);
	lua_pushinteger(L, lunatikS_getfd(session));
	return 1;
}

static int lsession_newstate(lua_State *L)
{
	struct lunatik_session *session = getsession(L);
	size_t len;
	const char *name = luaL_checklstring(L, 2, &len);
	lua_Integer maxalloc = luaL_optinteger(L, 3, DEFAULT_MAXALLOC_BYTES);
	struct lunatik_nl_state *state = lua_newuserdata(L, sizeof(struct lunatik_nl_state));

	if (len >= LUNATIK_NAME_MAXSIZE)
		luaL_argerror(L, 2, "name too long");

	strcpy(state->name, name);
	state->maxalloc = maxalloc;
	state->session = session;

	if (lunatikS_newstate(session, state)) {
		pusherrmsg(L, "Failed to create the state\n");
		return 2;
	}

	luaL_setmetatable(L, "states.control");

	return 1;
}

static int lstate_close(lua_State *L)
{
	struct lunatik_nl_state *s = getnlstate(L);
	if (lunatikS_closestate(s->session, s->name)){
		lua_pushboolean(L, false);
		return 1;
	}

	lua_pushboolean(L, true);
	return 1;
}

static int lstate_dostring(lua_State *L)
{
	struct lunatik_nl_state *s = getnlstate(L);
	struct lunatik_session *session = s->session;
	const char *name = s->name;
	size_t len;
	const char *payload = luaL_checklstring(L, 2, &len);
	const char *script_name = luaL_optstring(L, 3, "Lunatik");

	if (strlen(script_name) > LUNATIK_SCRIPTNAME_MAXSIZE) {
		printf("script name too long\n");
		goto error;
	}
	int status = lunatikS_dostring(session, name, payload, script_name, len);

	if (status)
		goto error;

	lua_pushnil(L);
	return 1;

error:
	lua_pushboolean(L, true);
	return 1;
}

static int lstate_getname(lua_State *L) {
	struct lunatik_nl_state *s = getnlstate(L);
	lua_pushstring(L, s->name);
	return 1;
}

static int lstate_getmaxalloc(lua_State *L) {
	struct lunatik_nl_state *s = getnlstate(L);
	lua_pushinteger(L, s->maxalloc);
	return 1;
}

static void buildlist(lua_State *L, struct lunatik_nl_state *states, size_t n);

static int lsession_list(lua_State *L)
{
	struct lunatik_session *session = getsession(L);
	struct states_list list;
	int status;

	status = lunatikS_list(session);
	if (status){
		lua_pushnil(L);
		return 1;
	}

	if (session->cb_result == CB_LIST_EMPTY) {
		buildlist(L, NULL, 0);
	} else {
		list = session->states_list;
		buildlist(L, list.states, list.list_size);
		free(list.states);
		list.list_size = 0;
	}

	return 1;
}

static void buildlist(lua_State *L, struct lunatik_nl_state *states, size_t n)
{
	size_t i;

	lua_newtable(L);
	for (i = 0; i < n; i++) {
		lua_newtable(L);
		lua_pushstring(L, states[i].name);
		lua_setfield(L, -2, "name");
		lua_pushinteger(L, states[i].maxalloc);
		lua_setfield(L, -2, "maxalloc");
		lua_pushinteger(L, states[i].curralloc);
		lua_setfield(L, -2, "curralloc");
		lua_seti(L, -2, i + 1);
	}
}
#ifndef _UNUSED
static int ldata_open(lua_State *L)
{
	int ret;
	uint32_t pid = generatepid(L, 1);
	struct nflua_data *dch = lua_newuserdata(L, sizeof(struct nflua_data));

	luaL_setmetatable(L, "nflua.data");
	ret = nflua_data_init(dch, pid);

	return ret < 0 ? pusherrno(L, ret) : 1;
}

static int ldata_gc(lua_State *L)
{
	struct nflua_data *dch = luaL_checkudata(L, 1, "nflua.data");
	if (nflua_data_is_open(dch)) nflua_data_close(dch);
	return 0;
}

static struct nflua_data *getdata(lua_State *L)
{
	struct nflua_data *dch = luaL_checkudata(L, 1, "nflua.data");
	if (!nflua_data_is_open(dch)) luaL_argerror(L, 1, "socket closed");
	return dch;
}

static int ldata_close(lua_State *L)
{
	struct nflua_data *dch = getdata(L);
	nflua_data_close(dch);
	lua_pushboolean(L, true);
	return 1;
}

static int ldata_getfd(lua_State *L)
{
	struct nflua_data *dch = getdata(L);
	lua_pushinteger(L, nflua_data_getsock(dch));
	return 1;
}

static int ldata_getpid(lua_State *L)
{
	struct nflua_data *dch = getdata(L);
	lua_pushinteger(L, nflua_data_getpid(dch));
	return 1;
}
#endif /* _UNUSED */

static int lstate_datasend(lua_State *L)
{
	struct lunatik_nl_state *state = getnlstate(L);
	size_t size;
	int err;
	const char *buffer = luamem_checkmemory(L, 2, &size);

	if (buffer == NULL) luaL_argerror(L, 2, "expected non NULL memory object");

	err = lunatik_datasend(state, buffer, size);
	err ? lua_pushnil(L) : lua_pushboolean(L, true);

	return 1;
}

#ifndef _UNUSED
static int ldata_receive(lua_State *L)
{
	struct nflua_data *dch = getdata(L);
	char state[NFLUA_NAME_MAXSIZE] = {0};
	size_t size, offset;
	int recv;
	char *buffer = luamem_checkmemory(L, 2, &size);

	if (buffer == NULL) luaL_argerror(L, 2, "expected non NULL memory object");

	offset = luaL_checkinteger(L, 3);
	if (offset >= size || size - offset < NFLUA_DATA_MAXSIZE)
		luaL_argerror(L, 3, "not enough space in buffer");

	recv = nflua_data_receive(dch, state, buffer + offset);
	if (recv < 0) return pusherrno(L, recv);

	lua_pushinteger(L, recv);
	lua_pushstring(L, state);

	return 2;
}
#endif /* _UNUSED */

static const luaL_Reg session_mt[] = {
	{"close", lsession_close},
	{"getfd", lsession_getfd},
	{"new", lsession_newstate},
	{"list", lsession_list},
	{"__gc", lsession_gc},
	{NULL, NULL}
};

static const luaL_Reg state_mt[] = {
	{"dostring", lstate_dostring},
	{"getname", lstate_getname},
	{"getmaxalloc", lstate_getmaxalloc},
	{"close", lstate_close},
	{"send", lstate_datasend},
	{NULL, NULL}
};

#ifndef _UNUSED
static const luaL_Reg data_mt[] = {
	{"close", ldata_close},
	{"getfd", ldata_getfd},
	{"getpid", ldata_getpid},
	{"__gc", ldata_gc},
	{NULL, NULL}
};
#endif /*_UNUSED*/

static const luaL_Reg lunatik_lib[] = {
	{"session", lsession_open},
	#ifndef _UNUSED
	{"data", ldata_open},
	#endif /*_UNUSED*/
	{NULL, NULL}
};

#ifndef _UNUSED
static void setconst(lua_State *L, const char *name, lua_Integer value)
{
	lua_pushinteger(L, value);
	lua_setfield(L, -2, name);
}
#endif

int luaopen_lunatik(lua_State *L)
{
	#ifndef _UNUSED
	luaL_requiref(L, "memory", luaopen_memory, 1);
	lua_pop(L, 1);
	#endif /*_UNUSED*/

	newclass(L, "lunatik.session", session_mt);
	newclass(L, "states.control", state_mt);
	#ifndef _UNUSED
	newclass(L, "nflua.data", data_mt);
	#endif /*_UNUSED*/

	luaL_newlib(L, lunatik_lib);

	#ifndef _UNUSED
	setconst(L, "datamaxsize", NFLUA_DATA_MAXSIZE);
	setconst(L, "defaultmaxallocbytes", DEFAULT_MAXALLOC_BYTES);
	setconst(L, "maxstates", NFLUA_MAX_STATES);
	setconst(L, "scriptnamemaxsize", NFLUA_SCRIPTNAME_MAXSIZE);
	setconst(L, "statenamemaxsize", NFLUA_NAME_MAXSIZE);
	#endif /*_UNUSED*/

	return 1;
}
