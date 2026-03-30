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

The Linux kernel generally prefers capitalized macro names. Lunatik follows this for constants, but allows `lowercase_with_underscores` for macros that behave like functions; these must be prefixed according to the module name (e.g., [`lunatik.h`](lunatik.h:27-30)).

```c
#define lunatik_issoftirq(opt)		((opt) & LUNATIK_OPT_SOFTIRQ)
#define lunatik_ismonitor(opt)		((opt) & LUNATIK_OPT_MONITOR)
```

## Includes

Includes should be grouped, with system/kernel headers first, followed by `lunatik.h`, and then any other project-specific headers. Lua headers are already included by `lunatik.h` and should not be included directly (e.g., [`lib/lualinux.c`](lib/lualinux.c:17-22)).

```c
#include <linux/random.h>
#include <linux/stat.h>

#include <lunatik.h>
/* #include "project_header.h" (if applicable) */
```

## Bracing Style

### Control Structures (if, for, while, do-while)

If any branch of a conditional statement requires braces, all branches must use them to maintain consistency and prevent logic errors (e.g., [`lunatik_core.c`](lunatik_core.c:59-66)).

```c
if (nptr == NULL) {
	return nsize <= osize ? optr : nptr;
} else if (optr != NULL) {
	memcpy(nptr, optr, min(osize, nsize));
	kvfree(optr);
}
```
