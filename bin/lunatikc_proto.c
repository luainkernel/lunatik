/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/*
* luaebpf.proto: hands a Lua function's prototype to the translator.
*
* The bytecode is what luaebpf compiles, and lunatikc is the only host that runs the kernel's
* own Lua, so the opcode numbering and the argument modes come from lopcodes.h and luaP_opmodes
* here rather than being restated in Lua and drifting from them.
*/

#include <lua.h>
#include <lauxlib.h>

#include <lobject.h>
#include <lopcodes.h>
#include <ldebug.h>

typedef struct luaebpf_opcode {
	const char *name;
	OpCode op;
} luaebpf_opcode_t;

/* names against the enum: a fenced-out or renamed opcode fails to build instead of drifting */
static const luaebpf_opcode_t luaebpf_opcodes[] = {
	{"MOVE", OP_MOVE}, {"LOADI", OP_LOADI}, {"LOADK", OP_LOADK}, {"LOADKX", OP_LOADKX},
	{"LOADFALSE", OP_LOADFALSE}, {"LFALSESKIP", OP_LFALSESKIP}, {"LOADTRUE", OP_LOADTRUE},
	{"LOADNIL", OP_LOADNIL}, {"GETUPVAL", OP_GETUPVAL}, {"SETUPVAL", OP_SETUPVAL},
	{"GETTABUP", OP_GETTABUP}, {"GETTABLE", OP_GETTABLE}, {"GETI", OP_GETI},
	{"GETFIELD", OP_GETFIELD}, {"SETTABUP", OP_SETTABUP}, {"SETTABLE", OP_SETTABLE},
	{"SETI", OP_SETI}, {"SETFIELD", OP_SETFIELD}, {"NEWTABLE", OP_NEWTABLE}, {"SELF", OP_SELF},
	{"ADDI", OP_ADDI}, {"ADDK", OP_ADDK}, {"SUBK", OP_SUBK}, {"MULK", OP_MULK}, {"MODK", OP_MODK},
	{"IDIVK", OP_IDIVK}, {"BANDK", OP_BANDK}, {"BORK", OP_BORK}, {"BXORK", OP_BXORK},
	{"SHLI", OP_SHLI}, {"SHRI", OP_SHRI}, {"ADD", OP_ADD}, {"SUB", OP_SUB}, {"MUL", OP_MUL},
	{"MOD", OP_MOD}, {"IDIV", OP_IDIV}, {"BAND", OP_BAND}, {"BOR", OP_BOR}, {"BXOR", OP_BXOR},
	{"SHL", OP_SHL}, {"SHR", OP_SHR}, {"MMBIN", OP_MMBIN}, {"MMBINI", OP_MMBINI},
	{"MMBINK", OP_MMBINK}, {"UNM", OP_UNM}, {"BNOT", OP_BNOT}, {"NOT", OP_NOT}, {"LEN", OP_LEN},
	{"CONCAT", OP_CONCAT}, {"CLOSE", OP_CLOSE}, {"TBC", OP_TBC}, {"JMP", OP_JMP}, {"EQ", OP_EQ},
	{"LT", OP_LT}, {"LE", OP_LE}, {"EQK", OP_EQK}, {"EQI", OP_EQI}, {"LTI", OP_LTI},
	{"LEI", OP_LEI}, {"GTI", OP_GTI}, {"GEI", OP_GEI}, {"TEST", OP_TEST}, {"TESTSET", OP_TESTSET},
	{"CALL", OP_CALL}, {"TAILCALL", OP_TAILCALL}, {"RETURN", OP_RETURN}, {"RETURN0", OP_RETURN0},
	{"RETURN1", OP_RETURN1}, {"FORLOOP", OP_FORLOOP}, {"FORPREP", OP_FORPREP},
	{"TFORPREP", OP_TFORPREP}, {"TFORCALL", OP_TFORCALL}, {"TFORLOOP", OP_TFORLOOP},
	{"SETLIST", OP_SETLIST}, {"CLOSURE", OP_CLOSURE}, {"VARARG", OP_VARARG},
	{"GETVARG", OP_GETVARG}, {"ERRNNIL", OP_ERRNNIL}, {"VARARGPREP", OP_VARARGPREP},
	{"EXTRAARG", OP_EXTRAARG},
};

static const char *const luaebpf_modenames[] = {"iABC", "ivABC", "iABx", "iAsBx", "iAx", "isJ"};

static void luaebpf_setinteger(lua_State *L, const char *field, lua_Integer value)
{
	lua_pushinteger(L, value);
	lua_setfield(L, -2, field);
}

static void luaebpf_setboolean(lua_State *L, const char *field, int value)
{
	lua_pushboolean(L, value);
	lua_setfield(L, -2, field);
}

static void luaebpf_pushinstruction(lua_State *L, Instruction i)
{
	OpCode op = GET_OPCODE(i);

	lua_createtable(L, 0, 7);
	luaebpf_setinteger(L, "op", op);
	switch (getOpMode(op)) {
	case iABC:
		luaebpf_setinteger(L, "a", GETARG_A(i));
		luaebpf_setinteger(L, "b", getarg(i, POS_B, SIZE_B));
		luaebpf_setinteger(L, "c", getarg(i, POS_C, SIZE_C));
		luaebpf_setinteger(L, "sb", sC2int(getarg(i, POS_B, SIZE_B)));
		luaebpf_setinteger(L, "sc", sC2int(getarg(i, POS_C, SIZE_C)));
		luaebpf_setboolean(L, "k", GETARG_k(i));
		break;
	case ivABC:
		luaebpf_setinteger(L, "a", GETARG_A(i));
		luaebpf_setinteger(L, "vb", getarg(i, POS_vB, SIZE_vB));
		luaebpf_setinteger(L, "vc", getarg(i, POS_vC, SIZE_vC));
		luaebpf_setboolean(L, "k", GETARG_k(i));
		break;
	case iABx:
		luaebpf_setinteger(L, "a", GETARG_A(i));
		luaebpf_setinteger(L, "bx", getarg(i, POS_Bx, SIZE_Bx));
		break;
	case iAsBx:
		luaebpf_setinteger(L, "a", GETARG_A(i));
		luaebpf_setinteger(L, "sbx", getarg(i, POS_Bx, SIZE_Bx) - OFFSET_sBx);
		break;
	case iAx:
		luaebpf_setinteger(L, "ax", getarg(i, POS_Ax, SIZE_Ax));
		break;
	case isJ:
		luaebpf_setinteger(L, "sj", getarg(i, POS_sJ, SIZE_sJ) - OFFSET_sJ);
		luaebpf_setboolean(L, "k", GETARG_k(i));
		break;
	}
}

static void luaebpf_pushconstant(lua_State *L, const TValue *o)
{
	if (ttisinteger(o))
		lua_pushinteger(L, ivalue(o));
	else if (ttisstring(o))
		lua_pushlstring(L, getstr(tsvalue(o)), tsslen(tsvalue(o)));
	else if (ttisboolean(o))
		lua_pushboolean(L, ttistrue(o));
	else
		lua_pushnil(L);
}

static void luaebpf_pushproto(lua_State *L, const Proto *p);

static void luaebpf_pusharray(lua_State *L, const Proto *p, const char *field, int size,
	void (*push)(lua_State *, const Proto *, int))
{
	int i;

	lua_createtable(L, size, 0);
	for (i = 0; i < size; i++) {
		push(L, p, i);
		lua_seti(L, -2, i + 1);
	}
	lua_setfield(L, -2, field);
}

static void luaebpf_pushcode(lua_State *L, const Proto *p, int i)
{
	luaebpf_pushinstruction(L, p->code[i]);
}

static void luaebpf_pushline(lua_State *L, const Proto *p, int i)
{
	lua_pushinteger(L, luaG_getfuncline(p, i));
}

static void luaebpf_pushk(lua_State *L, const Proto *p, int i)
{
	luaebpf_pushconstant(L, &p->k[i]);
}

static void luaebpf_pushupvalue(lua_State *L, const Proto *p, int i)
{
	const Upvaldesc *up = &p->upvalues[i];

	lua_createtable(L, 0, 3);
	if (up->name != NULL) {
		lua_pushlstring(L, getstr(up->name), tsslen(up->name));
		lua_setfield(L, -2, "name");
	}
	luaebpf_setboolean(L, "instack", up->instack);
	luaebpf_setinteger(L, "idx", up->idx);
}

static void luaebpf_pushnested(lua_State *L, const Proto *p, int i)
{
	luaebpf_pushproto(L, p->p[i]);
}

static void luaebpf_pushproto(lua_State *L, const Proto *p)
{
	luaL_checkstack(L, 6, "prototypes nested too deeply");
	lua_createtable(L, 0, 12);
	if (p->source != NULL) {
		lua_pushlstring(L, getstr(p->source), tsslen(p->source));
		lua_setfield(L, -2, "source");
	}
	luaebpf_setinteger(L, "linedefined", p->linedefined);
	luaebpf_setinteger(L, "lastlinedefined", p->lastlinedefined);
	luaebpf_setinteger(L, "numparams", p->numparams);
	luaebpf_setinteger(L, "maxstacksize", p->maxstacksize);
	luaebpf_setboolean(L, "isvararg", isvararg(p));
	luaebpf_setinteger(L, "nk", p->sizek); /* k holds nil constants, so # cannot count them */
	luaebpf_pusharray(L, p, "code", p->sizecode, luaebpf_pushcode);
	luaebpf_pusharray(L, p, "lines", p->sizecode, luaebpf_pushline);
	luaebpf_pusharray(L, p, "k", p->sizek, luaebpf_pushk);
	luaebpf_pusharray(L, p, "upvalues", p->sizeupvalues, luaebpf_pushupvalue);
	luaebpf_pusharray(L, p, "protos", p->sizep, luaebpf_pushnested);
}

/***
* Reads the prototype of a Lua function.
* @function read
* @tparam function fn a Lua function, not a C function
* @treturn table `{source, linedefined, lastlinedefined, numparams, isvararg, maxstacksize, nk,
*   code, lines, k, upvalues, protos}`
* @raise Lua function expected
*/
static int luaebpf_read(lua_State *L)
{
	luaL_checktype(L, 1, LUA_TFUNCTION);
	luaL_argcheck(L, !lua_iscfunction(L, 1), 1, "Lua function expected");
	luaebpf_pushproto(L, ((const LClosure *)lua_topointer(L, 1))->p);
	return 1;
}

static void luaebpf_pushopcodes(lua_State *L)
{
	size_t i;

	lua_createtable(L, 0, NUM_OPCODES);
	for (i = 0; i < sizeof(luaebpf_opcodes) / sizeof(luaebpf_opcodes[0]); i++) {
		lua_pushinteger(L, luaebpf_opcodes[i].op);
		lua_setfield(L, -2, luaebpf_opcodes[i].name);
	}
}

static void luaebpf_pushmodes(lua_State *L)
{
	size_t i;

	lua_createtable(L, 0, NUM_OPCODES);
	for (i = 0; i < sizeof(luaebpf_opcodes) / sizeof(luaebpf_opcodes[0]); i++) {
		OpCode op = luaebpf_opcodes[i].op;

		lua_createtable(L, 0, 6);
		lua_pushstring(L, luaebpf_modenames[getOpMode(op)]);
		lua_setfield(L, -2, "mode");
		luaebpf_setboolean(L, "a", testAMode(op));
		luaebpf_setboolean(L, "t", testTMode(op));
		luaebpf_setboolean(L, "it", testITMode(op));
		luaebpf_setboolean(L, "ot", testOTMode(op));
		luaebpf_setboolean(L, "mm", testMMMode(op));
		lua_setfield(L, -2, luaebpf_opcodes[i].name);
	}
}

static const luaL_Reg luaebpf_lib[] = {
	{"read", luaebpf_read},
	{NULL, NULL}
};

int luaopen_luaebpf_proto(lua_State *L)
{
	luaL_newlib(L, luaebpf_lib);
	luaebpf_pushopcodes(L);
	lua_setfield(L, -2, "opcodes");
	luaebpf_pushmodes(L);
	lua_setfield(L, -2, "modes");
	return 1;
}

