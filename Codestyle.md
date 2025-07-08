# Lunatik C Code Style Guide

This guide outlines the code style conventions observed in the `lunatik.h` header file, which should be followed for consistency across the Lunatik project. As a general rule, we tend to stick to [Linux kernel rules](https://www.kernel.org/doc/html/latest/process/coding-style.html).

## File Headers

All source files should begin with the SPDX license identifier and copyright information (e.g., [`lunatik.h`](lunatik.h:1-4)).

```c
/*
 * SPDX-FileCopyrightText: (c) 2023-2025 Ring Zero Desenvolvimento de Software LTDA
 * SPDX-License-Identifier: MIT OR GPL-2.0-only
 */
```

## Includes

Includes should be grouped, with system/kernel headers first, followed by Lua headers, and then project-specific headers. Use an empty line to separate groups (e.g., [`lunatik.h`](lunatik.h:9-16)).

```c
#include <linux/mutex.h>
#include <linux/spinlock.h>
#include <linux/slab.h>
#include <linux/kref.h>

#include <lua.h>
#include <lauxlib.h>

/* #include "project_header.h" (if applicable) */
```

## Indentation

Use tabs for indentation (e.g., [`lunatik.h`](lunatik.h:20-25)). For consistent alignment, especially within multi-line macros, it is recommended to configure your text editor to display tabs as 8 spaces.

## Bracing Style

### Functions

Functions use Allman style, with the opening brace on a new line after the function declaration (e.g., [`lunatik.h`](lunatik.h:37-43)).

```c
static inline bool lunatik_isready(lua_State *L)
{
	/* ... */
}
```

### Control Structures (if, for, while, do-while)

Control structures like `if`, `for`,`while` and `do-while` loops use K&R style
(e.g., [`lunatik.h`](lunatik.h:20-25), [`lunatik.h`](lunatik.h:47-52)).

```c
if (condition) {
	/* ... */
}

#define lunatik_handle(runtime, handler, ret, ...)	\
do {							\
	/* ... */					\
} while(0)
```

## Naming Conventions

### Macros

Macros follow two conventions:

* **Constants and Definitions**: Use `ALL_CAPS_WITH_UNDERSCORES` for macros defining constants or used for general definitions (e.g., [`lunatik.h`](lunatik.h:17), [`lunatik.h`](lunatik.h:190)).

    ```c
	#define LUNATIK_VERSION "Lunatik 3.6"
	#define LUNATIK_ERR_NULLPTR	"null-pointer dereference"
	```

* **Function-like Macros**: Use `lowercase_with_underscores` for macros that behave like functions ; prefix them according to the module name (e.g., [`lunatik.h`](lunatik.h:19), [`lunatik.h`](lunatik.h:27)).

    ```c
    #define lunatik_locker(o, mutex_op, spin_op)
    #define lunatik_newlock(o)
    ```

### Type Definitions (structs, enums)

Type definitions (structs, enums) use `snake_case` with a `_t` suffix for the `typedef` alias. The struct tag itself can use `_s` suffix (e.g., [`lunatik.h`](lunatik.h:64-68)).

```c
typedef struct lunatik_reg_s {
	const char *name;
	lua_Integer value;
} lunatik_reg_t;
```

### Functions

Functions use `snake_case` with a prefix (e.g., [`lunatik.h`](lunatik.h:37), [`lunatik.h`](lunatik.h:101)).

```c
static inline bool lunatik_isready(lua_State *L)
int lunatik_runtime(lunatik_object_t **pruntime, const char *script, bool sleep);
```

### Variables

Variables use `snake_case` (e.g., [`lunatik.h`](lunatik.h:38), [`lunatik.h`](lunatik.h:148)).

```c
lua_State *L;
lunatik_object_t *runtime;
```

## Macros

Multi-line macros should use `\` for line continuation and be enclosed in a `do { ... } while(0)` block to ensure proper semicolon usage and scope. Align the `\` characters for readability. Parameters should be enclosed in parentheses when used within the macro body to avoid unexpected operator precedence issues (e.g., `(o)->sleep`)
(e.g., [`lunatik.h`](lunatik.h:19-25), [`lunatik.h`](lunatik.h:46-52), [`lunatik.h`](lunatik.h:54-62)).

```c
#define lunatik_locker(o, mutex_op, spin_op)	\
do {						\
	if ((o)->sleep)				\
		mutex_op(&(o)->mutex);		\
	else					\
		spin_op(&(o)->spin);		\
} while(0)
```

## Comments

### Block Comments

Use C-style block comments (`/* ... */`) for multi-line comments, especially for file headers (e.g., [`lunatik.h`](lunatik.h:1-4)).

```c
/*
 * This is a block comment.
 */
```

### Inline Comments

Use C-style block comments (`/* ... */`) for inline comments or short explanations, consistent with kernel practice (e.g., [`lunatik.h`](lunatik.h:40)).

```c
static inline bool lunatik_isready(lua_State *L)
{
	bool ready; /* This is an inline comment */
	/* ... */
}
```

## Whitespace

### Binary Operators

Use spaces around binary operators (`=`, `+`, `-`, `*`, `/`, `==`, `!=`, etc.) (e.g., [`lunatik.h`](lunatik.h:4), [`lunatik.h`](lunatik.h:21)).

```c
total = a + b;
if (x == y)
```

### Commas

Use a space after commas (e.g., [`lunatik.h`](lunatik.h:27), [`lunatik.h`](lunatik.h:48)).

```c
handler(L, ## __VA_ARGS__);
const char *name, lua_Integer value;
```

### Function Calls

No space between the function name and the opening parenthesis (e.g., [`lunatik.h`](lunatik.h:37)).

```c
lunatik_isready(L)
```

### Unary Operators

No space between unary operators and their operand (e.g., `*ptr`, `&var`, `!condition`) (e.g., [`lunatik.h`](lunatik.h:98), [`lunatik.h`](lunatik.h:149)).

```c
*pruntime
&object->kref
!lunatik_getstate(runtime)
```

## Type Casting

Type casts should be explicit and use parentheses around the type (e.g., [`lunatik.h`](lunatik.h:32), [`lunatik.h`](lunatik.h:307)).

```c
(lunatik_object_t **)lua_getextraspace(L)
(char *)hook->field
```

## Function Parameters

Parameters in function declarations should be clearly typed. If a parameter is a pointer, the `*` should be next to the variable name (e.g., [`lunatik.h`](lunatik.h:37), [`lunatik.h`](lunatik.h:101)).

```c
lua_State *L
lunatik_object_t **pruntime
```

## Line Breaking

Staying under 80 characters per line is [preferred](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=bdc48fa11e46f867ea4d75fa59ee87a7f48be144), but [don’t stick to this rule against common sense](https://lkml.org/lkml/2020/5/29/1038).

When a line exceeds the preferred limit, break it at a logical point, such as after a comma in a function argument list, after a binary operator, or before a new expression. Indent the continued line with tabs to align with the start of the expression or argument list.

### Function Declarations and Calls

Break after commas in parameter lists, aligning subsequent parameters (e.g., [`lunatik.h`](lunatik.h:101)).

```c
int lunatik_runtime(lunatik_object_t **pruntime,
		    const char *script, bool sleep);
```

### Conditional Statements

Break long conditional expressions after logical operators, aligning the continuation (e.g., [`lunatik.h`](lunatik.h:245-246)).

```c
return class != NULL &&
       (pobject = luaL_testudata(L, ix, class->name)) != NULL ? *pobject : NULL;
```

## Line breaks, new lines and file Endings

All source files must end with two empty lines. Otherwise, there mustn’t be multiple consecutive empty lines in the files.

