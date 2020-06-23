# Lunatik API Documentation

This document provides a documentation of the portion of Lunatik responsable for thread-safe states management. One API is provided to user in order to access all operations related to states management.

The API is based on the data structure `lunatik_State` which is used to perform all needed operations.

## The `lunatik_state` struct

Defined at `states.h` as:

```c
typedef struct lunatik_state {
	struct hlist_node node;
	lua_State *L;
	spinlock_t lock;
	refcount_t users;
	size_t maxalloc;
	size_t curralloc;
	unsigned char name[LUNATIK_NAME_MAXSIZE];
} lunatik_State;
```

The elements in the struct has the following meaning:

 **`struct hlist_node node`**

Is a variable used by kernel hash table API to storage the `lunatik_State` structure.

**`lua_State L`**

Is the Lua state used by Lunatik to do all operations related to Lua.

**`spinlock_t lock`**

Is a spinlock variable used to manage concurrency control.

**`refcount_t users`**

Represents how many users are referring to a given `lunatik_State`.

**`size_t maxalloc`**

Represents the maximum memory that the lua state `L` can use.

**`size_t curralloc`**

Represents the current memory that the lua state `L` is using.

**`unsigned char name[LUNATIK_NAME_MAXSIZE]`**

Is the unique identifier to `lunatik_State`, used to search it in the kernel hash table, note that this is limited by `LUNATIK_NAME_MAXSIZE`.

## Functions offered by the API

**`lunatik_State *lunatik_statelookup(const char *name);`**

Searches for a `lunatik_State` with the name `name`. If a state with that name is found returns a pointer to the `lunatik_State` or `NULL` otherwise.

**`lunatik_State *lunatik_newstate(size_t maxalloc, const char *name)`**

Creates a `lunatik_State` with the max memory usage defined by `maxalloc` and a unique identifier to acess such state defined by `name`. Return a pointer to `lunatik_State` represeting the lunatik state or `NULL` if any errors occours during the creation.

**`int lunatik_close(const char *name)`**

Searchs and close a `lunatik_State`, returns `0` if no errors occours during this operation or `-1` otherwise.
