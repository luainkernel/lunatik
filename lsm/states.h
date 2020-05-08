#ifndef _LSM_STATES_
#define _LSM_STATES_

#include <lua.h>
#include <lauxlib.h>

struct lunatik_state
{
	lua_State *l;
	char *name;
};

int lsm_createState(const char *name);



#endif