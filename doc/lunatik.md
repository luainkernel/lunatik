# Lunatik API Documentation

## Introduction

This document provides a documentation of the Lunatik kernel module, this module is resposible for safe states management. Two main APIs are offered to the user, the first one has correlation with [network namespaces](https://man7.org/linux/man-pages/man8/ip-netns.8.html#DESCRIPTION), and provides a full isolation of the states based on each namespace, the second one provides a state management without relation with namespace, and all operations related to this API will be made based on the global network namespace.

The API is based on the data structure `lunatik_State` which is used to perform all needed operations.

## The `lunatik_State` struct

Defined at `states.h` as:

```c
typedef struct lunatik_state {
	struct hlist_node node;
	struct lunatik_instance instance;
	struct genl_info usr_state_info;
	lua_State *L;
	char *code_buffer;
	int buffer_offset;
	spinlock_t lock;
	refcount_t users;
	size_t maxalloc;
	size_t curralloc;
	size_t scriptsize;
	unsigned char name[LUNATIK_NAME_MAXSIZE];
} lunatik_State;
```

The elements in the struct has the following meaning:

**`struct hlist_node node`**

Is a variable used by kernel hash table API to storage the `lunatik_State` structure.

**`struct lunatik_instance instance`**

The instance of lunatik that some state belongs to. This is used to have access to informations related to the instance of lunatik that that state belongs. As mentioned at the [introduction](#introduction), its possible to have multiples set of states stored based on network namespaces, we know in what set this state belongs through this variable.

**`struct genl_info usr_state_info`**

Information related to the user space API. This variable is used to hold information about the user space API and consequently send needed informations through generic netlink.

**`lua_State L`**

Is the Lua state used by Lunatik to do all operations related to Lua.

**`char *code_buffer`**

A buffer used to store code through multiples function calls and contexts switchs between kernel and user space.

**`int buffer_offset`**

The buffer offset, used to hold information about where the cursor of `code_buffer` is at some time.

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

## Namespace independent functions

"Namespace independent functions" means that you don't have concern about namespaces management, this can be used when your aplication don't need to work isolated of other aplications. If this is not the case, then use the namespace dependent functions.

#### `lunatik_State *lunatik_statelookup(const char *name)`

Searches for a state with the name `name`. If a state with that name is found returns a pointer to the `lunatik_State`, returns `NULL` otherwise.

#### `lunatik_State *lunatik_newstate(const char *name, size_t maxalloc)`

Creates a `lunatik_State` with the max memory usage defined by `maxalloc` and a unique identifier to acess such state defined by `name`. Return a pointer to `lunatik_State` represeting the lunatik state or `NULL` if any errors occours during the creation.

#### `int lunatik_close(const char *name)`

Searchs and close a `lunatik_State` with the name `name`, returns `0` if no errors occours during this operation and `-1` if any error occours.

#### `bool lunatik_getstate(lunatik_State *s)`

Tries to get a reference to the state `s`, return `true` if such reference is succesfully acquired and `false` otherwise.
It's important to get a reference to the state before perform any action because this is the way that Lunatik knows if there is someone using the state or not (to close a state for example), so if you don't acquire the state to perform the action, the state can be closed and you will try to perform actions on a memory area that have been freed.

#### `void lunatik_putstate(lunatik_State *s)`

Put back the reference of the state. This tells the lunatik that you're are done with that state.

## Namespace depedent functions

#### `lunatik_State *lunatik_netnewstate(const char *name, size_t maxalloc, struct net *net)`

Does the same of [`lunatik_newstate`](#lunatik_state-lunatik_newstatesize_t-maxalloc-const-char-name) but stores the state on the lunatik instance present on the network namespace referenced by `net`.

#### `int lunatik_netclosestate(const char *name, struct net *net)`

Does the same of [`lunatik_close`](#int-lunatik_closeconst-char-name) but closes the state stored on the lunatik instance present on the namespace referenced by `net`.

#### `lunatik_State *lunatik_netstatelookup(const char *name, struct net *net)`

Does the same of [`lunatik_statelookup`](#lunatik_state-lunatik_statelookupconst-char-name) but searching on the lunatik instance present on the namespace referenced by `net`.
