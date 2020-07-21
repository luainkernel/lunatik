/*
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
#include <lmemlib.h>
#include <lua.h>
#include <nflua.h>

extern int luaopen_memory(lua_State *L);

#define DEFAULT_MAXALLOC_BYTES	(32 * 1024)

struct control {
	struct nflua_control ctrl;
	struct nflua_response response;
	char buffer[NFLUA_LIST_MAXSIZE];
};

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

static int pushioresult(lua_State *L, int code)
{
	if (code >= 0) {
		lua_pushboolean(L, true);
		return 1;
	}
	return pusherrno(L, code);
}

static void newclass(lua_State *L, const char *name,
				const luaL_Reg mt[])
{
	luaL_newmetatable(L, name);
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	luaL_setfuncs(L, mt, 0);
	lua_pop(L, 1);
}

static uint32_t generatepid(lua_State *L, int arg)
{
	const uint32_t mask = 1 << 31;

	switch (lua_type(L, 1)) {
	case LUA_TNUMBER: {
		uint32_t pid = lua_tointeger(L, arg);
		if (pid & mask)
			luaL_argerror(L, arg, "must be in range [0, 2^31)");
		return pid;
	}
	case LUA_TNIL:
	case LUA_TNONE: {
		static uint16_t globaln = 0;
		uint32_t n = __sync_fetch_and_add(&globaln, 1);
		return (n << 16) | (getpid() & 0xFFFF) | mask;
	}
	default:
		luaL_argerror(L, arg, "must be integer or nil");
	}

	return 0;
}

static int lcontrol_open(lua_State *L)
{
	int ret;
	uint32_t pid = generatepid(L, 1);
	struct control *c = lua_newuserdata(L, sizeof(struct control));

	luaL_setmetatable(L, "nflua.control");
	ret = nflua_control_init(&c->ctrl, pid);

	return ret < 0 ? pusherrno(L, ret) : 1;
}

static int lcontrol_gc(lua_State *L)
{
	struct control *c = luaL_checkudata(L, 1, "nflua.control");
	if (nflua_control_is_open(&c->ctrl)) nflua_control_close(&c->ctrl);
	return 0;
}

static struct control *getcontrol(lua_State *L)
{
	struct control *c = luaL_checkudata(L, 1, "nflua.control");
	if (!nflua_control_is_open(&c->ctrl))
		luaL_argerror(L, 1, "socket closed");
	return c;
}

static int lcontrol_close(lua_State *L)
{
	struct control *c = getcontrol(L);
	nflua_control_close(&c->ctrl);
	lua_pushboolean(L, true);
	return 1;
}

static int lcontrol_getfd(lua_State *L)
{
	struct control *c = getcontrol(L);
	lua_pushinteger(L, nflua_control_getsock(&c->ctrl));
	return 1;
}

static int lcontrol_getpid(lua_State *L)
{
	struct control *c = getcontrol(L);
	lua_pushinteger(L, nflua_control_getpid(&c->ctrl));
	return 1;
}

static int lcontrol_getstate(lua_State *L)
{
	static const char *tostr[] = {
		[NFLUA_LINK_READY] = "ready",
		[NFLUA_SENDING_REQUEST] = "sending",
		[NFLUA_PENDING_REPLY] = "waiting",
		[NFLUA_RECEIVING_REPLY] = "receiving",
		[NFLUA_PROTOCOL_OUTOFSYNC] = "failed",
		[NFLUA_SOCKET_CLOSED] = "closed"
	};
	struct control *c = getcontrol(L);
	int state = nflua_control_getstate(&c->ctrl);

	if (state < NFLUA_LINK_READY || state > NFLUA_SOCKET_CLOSED)
		return pusherrmsg(L, "unknown state");

	lua_pushstring(L, tostr[state]);

	return 1;
}

static int lcontrol_create(lua_State *L)
{
	struct control *c = getcontrol(L);
	size_t len;
	const char *name = luaL_checklstring(L, 2, &len);
	lua_Integer maxalloc = luaL_optinteger(L, 3, DEFAULT_MAXALLOC_BYTES);
	struct nflua_nl_state state;

	if (len >= NFLUA_NAME_MAXSIZE)
		luaL_argerror(L, 2, "name too long");

	strcpy(state.name, name);
	state.maxalloc = maxalloc;

	return pushioresult(L, nflua_control_create(&c->ctrl, &state));
}

static int lcontrol_destroy(lua_State *L)
{
	struct control *c = getcontrol(L);
	const char *name = luaL_checkstring(L, 2);
	return pushioresult(L, nflua_control_destroy(&c->ctrl, name));
}

static int lcontrol_execute(lua_State *L)
{
	struct control *c = getcontrol(L);
	const char *name = luaL_checkstring(L, 2);
	size_t len;
	const char *payload = luaL_checklstring(L, 3, &len);
	const char *scriptname = luaL_optstring(L, 4, payload);
	int status = nflua_control_execute(&c->ctrl, name, scriptname,
		payload, len);

	if (status > 0) return pusherrmsg(L, "pending");
	return pushioresult(L, status);
}

static int lcontrol_list(lua_State *L)
{
	struct control *c = getcontrol(L);
	return pushioresult(L, nflua_control_list(&c->ctrl));
}

static void buildlist(lua_State *L, struct nflua_nl_state *states, size_t n)
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

static int lcontrol_receive(lua_State *L)
{
	struct control *c = getcontrol(L);
	int status = nflua_control_receive(&c->ctrl, &c->response, c->buffer);

	if (status < 0) return pusherrno(L, status);
	if (status > 0) return pusherrmsg(L, "pending");

	switch (c->response.type) {
	case NLMSG_ERROR:
		return pusherrmsg(L, "operation could not be completed");
	case NFLMSG_CREATE:
	case NFLMSG_EXECUTE:
	case NFLMSG_DESTROY:
		lua_pushboolean(L, true);
		return 1;
	case NFLMSG_LIST:
		buildlist(L, (struct nflua_nl_state *)c->buffer,
			c->response.count);
		return 1;
	default:
		return pusherrmsg(L, "unknown response");
	}

	return 0;
}

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

static int ldata_send(lua_State *L)
{
	struct nflua_data *dch = getdata(L);
	const char *name = luaL_checkstring(L, 2);
	size_t size;
	const char *buffer = luamem_checkmemory(L, 3, &size);

	if (buffer == NULL) luaL_argerror(L, 3, "expected non NULL memory object");

	return pushioresult(L, nflua_data_send(dch, name, buffer, size));
}

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

static const luaL_Reg control_mt[] = {
	{"close", lcontrol_close},
	{"getfd", lcontrol_getfd},
	{"getpid", lcontrol_getpid},
	{"getstate", lcontrol_getstate},
	{"create", lcontrol_create},
	{"destroy", lcontrol_destroy},
	{"execute", lcontrol_execute},
	{"list", lcontrol_list},
	{"receive", lcontrol_receive},
	{"__gc", lcontrol_gc},
	{NULL, NULL}
};

static const luaL_Reg data_mt[] = {
	{"close", ldata_close},
	{"getfd", ldata_getfd},
	{"getpid", ldata_getpid},
	{"send", ldata_send},
	{"receive", ldata_receive},
	{"__gc", ldata_gc},
	{NULL, NULL}
};

static const luaL_Reg nflua_lib[] = {
	{"control", lcontrol_open},
	{"data", ldata_open},
	{NULL, NULL}
};

static void setconst(lua_State *L, const char *name, lua_Integer value)
{
	lua_pushinteger(L, value);
	lua_setfield(L, -2, name);
}

int luaopen_nflua(lua_State *L)
{
	luaL_requiref(L, "memory", luaopen_memory, 1);
	lua_pop(L, 1);

	newclass(L, "nflua.control", control_mt);
	newclass(L, "nflua.data", data_mt);

	luaL_newlib(L, nflua_lib);

	setconst(L, "datamaxsize", NFLUA_DATA_MAXSIZE);
	setconst(L, "defaultmaxallocbytes", DEFAULT_MAXALLOC_BYTES);
	setconst(L, "maxstates", NFLUA_MAX_STATES);
	setconst(L, "scriptnamemaxsize", NFLUA_SCRIPTNAME_MAXSIZE);
	setconst(L, "statenamemaxsize", NFLUA_NAME_MAXSIZE);

	return 1;
}
