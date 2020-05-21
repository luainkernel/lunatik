#ifndef states_h
#define states_h

#include <lauxlib.h>

#define KLUA_MAX_NAMESIZE 64

#define STATE_CREATION_ERROR   0
#define STATE_CREATION_SUCCESS 1

#define STATE_CREATION_ERROR   0
#define STATE_CREATION_SUCCESS 1

#define STATE_DELETION_ERROR   0
#define STATE_DELETION_SUCCESS 1

#define CODE_EXEC_ERROR        0
#define CODE_EXEC_SUCCESS      1

struct klua_state {
	struct hlist_node node;
	lua_State *L;
	spinlock_t lock;
	refcount_t refcount;
	char name[KLUA_MAX_NAMESIZE];
};

int klua_createstate(const char *name);
int klua_deletestate(const char *name);
void klua_liststates(void);
int klua_execute(const char *name, const char *code);

#endif