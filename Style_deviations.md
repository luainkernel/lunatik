# Lunatik Style Deviations

This document outlines the specific areas where the Lunatik project deviates from the [Linux kernel coding style](https://www.kernel.org/doc/html/latest/process/coding-style.html). For any style convention not explicitly mentioned here, the Linux kernel rules must be followed.

## Line Breaking

Staying under 120 characters per line is _preferred_, but [don’t stick to this rule against common sense](https://lkml.org/lkml/2020/5/29/1038). This differs from the kernel's 80-character preference to better accommodate modern displays and long Lua-C integration signatures.

When a line exceeds the preferred limit, break it at a logical point and indent the continued line with **two tabs** to avoid confusion with the function body or subsequent logic (e.g., [`lunatik.h`](lunatik.h:114)).

```c
int lunatik_runtime(lunatik_object_t **pruntime,
		const char *script, lunatik_opt_t opt);
```

## Type Definitions (structs, enums)

Unlike the Linux kernel, which discourages the use of `typedef` for structures, Lunatik uses them to provide a cleaner interface for Lua integration. Type definitions use `snake_case` with a `_t` suffix for the `typedef` alias. The struct tag itself should use a `_s` suffix (e.g., [`lunatik.h`](lunatik.h:94-104)).

```c
typedef struct lunatik_object_s {
	struct kref kref;
	/* ... */
} lunatik_object_t;
```

## Naming Conventions

### Macros

Lunatik follows the Linux kernel's preference for **capitalized macro names** for constants, bitmask options, and initialization/boilerplate macros (e.g., [`lunatik.h`](lunatik.h:21-25,329)).

```c
#define LUNATIK_OPT_SOFTIRQ	((__force lunatik_opt_t)(1U << 0))
#define LUNATIK_NEWLIB(libname, funcs, classes, namespaces) ...
```

However, it allows `lowercase_with_underscores` for macros that behave like functions; these must be prefixed according to the module name (e.g., [`lunatik.h`](lunatik.h:27-30)).

```c
#define lunatik_issoftirq(opt)		((opt) & LUNATIK_OPT_SOFTIRQ)
```

## Includes

Includes should be grouped, with system/kernel headers first, followed by `lunatik.h`, and then any other project-specific headers. Lua headers are already included by `lunatik.h` and should not be included directly (e.g., [`lib/lualinux.c`](lib/lualinux.c:17-22)).

```c
#include <linux/random.h>
#include <linux/stat.h>

#include <lunatik.h>
/* #include "project_header.h" (if applicable) */
```

## Documentation Comments

Lunatik uses **LDoc-style** comments (`/*** ... */`) for both file-level and function-level documentation. This deviates from the [Linux kernel-doc format](https://www.kernel.org/doc/html/latest/doc-guide/kernel-doc.html) (`/** ... */`) to better support standard Lua documentation tools.

Documentation blocks should use specific tags to describe types and behaviors:
*   `@tparam`: Defines parameter types (e.g., `string|data`). Use `[opt]` for optional parameters.
*   `@treturn`: Defines the return type.
*   `@raise`: Describes conditions that trigger a Lua error.
*   `@see`: References related functions or modules.

```c
/***
* Sends a message through the socket.
*
* @function send
* @tparam string|data message The message to send; a data object avoids string allocation.
* @tparam[opt] integer|string addr Destination address (family-dependent).
* @tparam[opt] integer port Destination port (required for `AF_INET`).
* @treturn integer The number of bytes sent.
* @raise Error if the send operation fails.
* @see net.aton
*/
static int luasocket_send(lua_State *L)
```

## Pointer Comparisons

Unlike the Linux kernel, which prefers implicit boolean evaluation for pointers (e.g., `if (!ptr)`), Lunatik uses **explicit comparisons** to improve clarity and maintain consistency with Lua's explicit handling of `nil` (e.g., [`lunatik_core.c`](lunatik_core.c:211)).

```c
if (ptr == NULL) /* Preferred in Lunatik */
if (!ptr)        /* Discouraged in Lunatik */
```

## Return Statements

Unlike the Linux kernel, which forbids parentheses around return values (e.g., `return a;`), Lunatik allows them when it improves readability or is used within complex macros (e.g., [`lunatik_aux.c`](lunatik_aux.c:105)).

```c
return (void *)__lunatik_lookup(symbol); /* Accepted in Lunatik */
```

## Switch Statements

Lunatik indents `case` labels relative to the `switch` statement to maintain a clear visual hierarchy, whereas the Linux kernel prefers they be aligned (e.g., [`lunatik_val.c`](lunatik_val.c:11-12)).

```c
switch (value->type) {
	case LUA_TNIL: /* Indented in Lunatik */
		break;
}
```

## Assignments in Conditionals

Lunatik frequently performs assignments within `if` conditions to maintain concise Lua-C integration logic (e.g., [`lunatik_core.c`](lunatik_core.c:231)).

```c
if ((L = luaL_newstate()) == NULL)
```
