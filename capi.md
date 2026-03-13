# Lunatik C API

```C
#include <lunatik.h>
```

## Types

### lunatik\_class\_t
```C
typedef struct lunatik_class_s {
	const char     *name;
	const luaL_Reg *methods;
	void          (*release)(void *);
	bool            sleep;
	bool            shared;
	bool            pointer;
} lunatik_class_t;
```
Describes a Lunatik object class.

- `name`: class name; used as the argument to `require` and to identify the class.
- `methods`: `NULL`-terminated array of Lua methods registered in the metatable.
- `release`: called when the object's reference counter reaches zero; may be `NULL`.
- `sleep`: if `true`, objects use a mutex and `GFP_KERNEL`; if `false`, a spinlock and `GFP_ATOMIC`.
- `shared`: if `true`, registers a monitored metatable that wraps method calls with a lock, enabling safe concurrent access from multiple runtimes. Required for classes whose instances may be created with `monitor=true` or `clone=true`.
- `pointer`: if `true`, `object->private` holds an external pointer — Lunatik will not free it on release.

### lunatik\_reg\_t
```C
typedef struct lunatik_reg_s {
	const char  *name;
	lua_Integer  value;
} lunatik_reg_t;
```
A name–integer-value pair used to export constants to Lua. Arrays must be terminated by `{NULL, 0}`.

### lunatik\_namespace\_t
```C
typedef struct lunatik_namespace_s {
	const char          *name;
	const lunatik_reg_t *reg;
} lunatik_namespace_t;
```
A named table of `lunatik_reg_t` constants. Passed to `LUNATIK_NEWLIB` to create sub-tables
in the module table (e.g., `netfilter.action`, `netfilter.family`). Terminated by `{NULL, NULL}`.

---

## Runtime

### lunatik\_runtime
```C
int lunatik_runtime(lunatik_object_t **pruntime, const char *script, bool sleep);
```
_lunatik\_runtime()_ creates a new `runtime` environment then loads and runs the script
`/lib/modules/lua/<script>.lua` as the entry point for this environment.
It _must_ only be called from _process context_.
The `runtime` environment is a Lunatik object that holds
a [Lua state](https://www.lua.org/manual/5.5/manual.html#lua_State).
Lunatik objects are special
Lua [userdata](https://www.lua.org/manual/5.5/manual.html#2.1)
which also hold
a [lock type](https://docs.kernel.org/locking/locktypes.html) and
a [reference counter](https://www.kernel.org/doc/Documentation/kref.txt).
If `sleep` is _true_, _lunatik\_runtime()_ will use a
[mutex](https://docs.kernel.org/locking/mutex-design.html)
for locking the `runtime` environment and the
[GFP\_KERNEL](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html)
flag for allocating new memory later on
[lunatik\_run()](#lunatik_run) calls.
Otherwise, it will use a [spinlock](https://docs.kernel.org/locking/locktypes.html#raw-spinlock-t-and-spinlock-t) and [GFP\_ATOMIC](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html).
_lunatik\_runtime()_ opens the Lua standard libraries
[present on Lunatik](https://github.com/luainkernel/lunatik#c-api).
If successful, _lunatik\_runtime()_ sets the address pointed by `pruntime` and
[Lua's extra space](https://www.lua.org/manual/5.5/manual.html#lua_getextraspace)
with a pointer for the new created `runtime` environment,
sets the _reference counter_ to `1` and then returns `0`.
Otherwise, it returns `-ENOMEM`, if insufficient memory is available;
or `-EINVAL`, if it fails to load or run the `script`.

#### Example
```Lua
-- /lib/modules/lua/mydevice.lua
function myread(len, off)
	return "42"
end
```

```C
static lunatik_object_t *runtime;

static int __init mydevice_init(void)
{
	return lunatik_runtime(&runtime, "mydevice", true);
}
```

### lunatik\_stop
```C
int lunatik_stop(lunatik_object_t *runtime);
```
_lunatik\_stop()_
[closes](https://www.lua.org/manual/5.5/manual.html#lua_close)
the
[Lua state](https://www.lua.org/manual/5.5/manual.html#lua_State)
created for this `runtime` environment and decrements the
[reference counter](https://www.kernel.org/doc/Documentation/kref.txt).
Once the reference counter is decremented to zero, the
[lock type](https://docs.kernel.org/locking/locktypes.html)
and the memory allocated for the `runtime` environment are released.
If the `runtime` environment has been released, it returns `1`;
otherwise, it returns `0`.

### lunatik\_run
```C
void lunatik_run(lunatik_object_t *runtime, <inttype> (*handler)(...), <inttype> &ret, ...);
```
_lunatik\_run()_ locks the `runtime` environment and calls the `handler`
passing the associated Lua state as the first argument followed by the variadic arguments.
If the Lua state has been closed, `ret` is set with `-ENXIO`;
otherwise, `ret` is set with the result of `handler(L, ...)` call.
Then, it restores the Lua stack and unlocks the `runtime` environment.
It is defined as a macro.

#### Example
```C
static int l_read(lua_State *L, char *buf, size_t len, loff_t *off)
{
	size_t llen;
	const char *lbuf;

	lua_getglobal(L, "myread");
	lua_pushinteger(L, len);
	lua_pushinteger(L, *off);
	if (lua_pcall(L, 2, 2, 0) != LUA_OK) { /* calls myread(len, off) */
		pr_err("%s\n", lua_tostring(L, -1));
		return -ECANCELED;
	}

	lbuf = lua_tolstring(L, -2, &llen);
	llen = min(len, llen);
	if (copy_to_user(buf, lbuf, llen) != 0)
		return -EFAULT;

	*off = (loff_t)luaL_optinteger(L, -1, *off + llen);
	return (ssize_t)llen;
}

static ssize_t mydevice_read(struct file *f, char *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	lunatik_object_t *runtime = (lunatik_object_t *)f->private_data;

	lunatik_run(runtime, l_read, ret, buf, len, off);
	return ret;
}
```

### lunatik\_handle
```C
void lunatik_handle(lunatik_object_t *runtime, <inttype> (*handler)(...), <inttype> &ret, ...);
```
Like `lunatik_run`, but without acquiring the runtime lock. Use this when the lock is
already held, or when calling from within a `lunatik_run` handler. Defined as a macro.

### lunatik\_toruntime
```C
lunatik_object_t *lunatik_toruntime(lua_State *L);
```
Returns the `runtime` environment referenced by `L`'s
[extra space](https://www.lua.org/manual/5.5/manual.html#lua_getextraspace).
Defined as a macro.

### lunatik\_isready
```C
bool lunatik_isready(lua_State *L);
```
Returns `true` if the script associated with `L` has finished loading (i.e., the top-level
chunk has returned). Use this to guard operations that must not run during module
initialization — for example, spawning a kernel thread from a `runner.spawn` callback.

---

## Object Lifecycle

### lunatik\_newobject
```C
lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size, bool monitor, bool clone);
```
_lunatik\_newobject()_ allocates a new Lunatik object and pushes a userdata
containing a pointer to the object onto the Lua stack.
- If `monitor` is _true_, method calls are wrapped with the class lock, enabling safe concurrent
  access from multiple runtimes. Requires `class->monitor = true`.
- If `clone` is _true_, the object may be shared across runtimes via RCU or `resume()`.
- If `class->sleep` is _true_, it uses a mutex and `GFP_KERNEL`; otherwise a spinlock and `GFP_ATOMIC`.

It allocates `size` bytes for the object's private data, unless `class->pointer` is _true_,
in which case `object->private` is expected to be set by the caller.

### lunatik\_createobject
```C
lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, bool sleep, bool monitor, bool clone);
```
_lunatik\_createobject()_ creates a Lunatik object independently of any Lua
state. This is intended for objects created in C that will be shared
with Lua runtimes later via `lunatik_cloneobject`.

It allocates memory with `GFP_KERNEL` if `sleep` is _true_, or `GFP_ATOMIC` otherwise.
Returns a pointer to the `lunatik_object_t` on success, or `NULL` if memory allocation fails.

### lunatik\_cloneobject
```C
void lunatik_cloneobject(lua_State *L, lunatik_object_t *object);
```
_lunatik\_cloneobject()_ pushes `object` onto the Lua stack as a userdata with the correct
metatable. It calls `lunatik_require(L, class->name)` internally to ensure the class
metatable is registered even if the script never called `require` itself.
The object must have been created with `clone = true`; otherwise a Lua error is raised.

Use together with `lunatik_createobject` for C-owned objects that must be passed to Lua:
```C
obj = lunatik_createobject(&luafoo_class, sizeof(foo_t), true, true);
lunatik_run(runtime, my_handler, ret, obj);

/* inside my_handler: */
lunatik_cloneobject(L, obj);   /* pushes userdata, increments refcount */
lunatik_getobject(obj);
```

### lunatik\_getobject
```C
void lunatik_getobject(lunatik_object_t *object);
```
Increments the [reference counter](https://www.kernel.org/doc/Documentation/kref.txt) of `object`.

### lunatik\_putobject
```C
int lunatik_putobject(lunatik_object_t *object);
```
Decrements the [reference counter](https://www.kernel.org/doc/Documentation/kref.txt) of `object`.
If the object has been released, returns `1`; otherwise returns `0`.

---

## Object Access

### lunatik\_checkobject
```C
lunatik_object_t *lunatik_checkobject(lua_State *L, int i);
```
Returns the Lunatik object at stack position `i`. Raises a Lua error if the value is not a
Lunatik object. Defined as a macro.

### lunatik\_toobject
```C
lunatik_object_t *lunatik_toobject(lua_State *L, int i);
```
Returns the Lunatik object at stack position `i` without type checking. Returns `NULL` if
the value is not a userdata. Defined as a macro.

### LUNATIK\_OBJECTCHECKER
```C
#define LUNATIK_OBJECTCHECKER(checker, T)
```
Generates a `static inline` function `T checker(lua_State *L, int ix)` that returns
`object->private` cast to `T`. Performs a full object check; raises a Lua error if the
value at `ix` is not a valid Lunatik object.

### LUNATIK\_PRIVATECHECKER
```C
#define LUNATIK_PRIVATECHECKER(checker, T, ...)
```
Like `LUNATIK_OBJECTCHECKER`, but also guards against use-after-free by checking that
`private != NULL` before returning. The optional `...` may include additional validation
statements (e.g., checking a secondary field) that are executed before `return private`.

---

## Registry and Attach/Detach

The registry pattern keeps pre-allocated objects alive across `lunatik_run` calls without
exposing them to the GC:

```
// Registration (once, at hook setup):
lunatik_attach(L, obj, field, luafoo_new)   // creates object, stores in registry, sets obj->field

// Use (on each callback):
lunatik_getregistry(L, obj->field)          // pushes userdata
lunatik_object_t *o = lunatik_toobject(L, -1);
luafoo_reset(o, ...);                       // update the wrapped pointer

// Teardown (on unregister):
lunatik_detach(runtime, obj, field)         // unregisters and nulls obj->field
```

### lunatik\_registerobject
```C
void lunatik_registerobject(lua_State *L, int ix, lunatik_object_t *object);
```
Pins `object` and its `private` pointer in `LUA_REGISTRYINDEX`, preventing garbage
collection. `ix` is typically the index of the opts table passed to the registration function.

### lunatik\_unregisterobject
```C
void lunatik_unregisterobject(lua_State *L, lunatik_object_t *object);
```
Removes `object` and its `private` pointer from the registry, allowing GC to collect them.

### lunatik\_getregistry
```C
int lunatik_getregistry(lua_State *L, void *key);
```
Pushes the value stored in `LUA_REGISTRYINDEX` at `key` onto the Lua stack and returns
its type. Defined as a macro wrapping `lua_rawgetp`.

### lunatik\_attach
```C
void lunatik_attach(lua_State *L, obj, field, new_fn, ...);
```
Creates a new object by calling `new_fn(L, ...)`, stores it in `LUA_REGISTRYINDEX` keyed by
the returned pointer, sets `obj->field` to the result, and pops the userdata from the stack.
Defined as a macro.

### lunatik\_detach
```C
void lunatik_detach(lunatik_object_t *runtime, obj, field);
```
Unregisters `obj->field` from the registry and sets `obj->field = NULL`. Safe to call when
the Lua state may already be closed (e.g., from `release` after `lunatik_stop`). Defined as a macro.

---

## Error Handling

### lunatik\_throw
```C
void lunatik_throw(lua_State *L, int ret);
```
Pushes the POSIX error name for `-ret` (e.g., `"ENOMEM"`) as a string and calls `lua_error`.
Used to convert negative kernel error codes into Lua errors.

### lunatik\_try
```C
void lunatik_try(lua_State *L, op, ...);
```
Calls `op(...)`. If the return value is negative, calls `lunatik_throw`. Defined as a macro.

### lunatik\_tryret
```C
void lunatik_tryret(lua_State *L, ret, op, ...);
```
Like `lunatik_try`, but stores the return value in `ret` before checking. Defined as a macro.

---

## Table Fields

These macros read fields from a Lua table at stack index `idx` into a C struct.

### lunatik\_setinteger
```C
void lunatik_setinteger(lua_State *L, int idx, hook, field);
```
Reads a required integer field named `field` from the table at `idx` into `hook->field`.
Raises a Lua error if the field is missing or not a number.

### lunatik\_optinteger
```C
void lunatik_optinteger(lua_State *L, int idx, priv, field, opt);
```
Reads an optional integer field named `field` from the table at `idx` into `priv->field`.
Falls back to `opt` if the field is absent or nil.

### lunatik\_setstring
```C
void lunatik_setstring(lua_State *L, int idx, hook, field, maxlen);
```
Reads a required string field named `field` from the table at `idx` into `hook->field`,
truncated to `maxlen` bytes. Raises a Lua error if the field is missing or not a string.

---

## Module Definition

### LUNATIK\_NEWLIB
```C
#define LUNATIK_NEWLIB(libname, funcs, class, namespaces)
```
Defines and exports the `luaopen_<libname>` entry point using `EXPORT_SYMBOL_GPL`.

- `funcs`: `luaL_Reg[]` of Lua-callable functions (the module table).
- `class`: pointer to a `lunatik_class_t`, or `NULL` if the module defines no object type.
- `namespaces`: `lunatik_namespace_t[]` of constant sub-tables, or `NULL`.

When `class != NULL`, `LUNATIK_NEWLIB` registers the class metatable(s). When
`namespaces != NULL`, it creates constant sub-tables inside the module table.

#### Example
```C
static const luaL_Reg luafoo_lib[] = {
	{"new", luafoo_new},
	{NULL, NULL},
};

static const lunatik_reg_t luafoo_flags[] = {
	{"BAR", FOO_BAR},
	{NULL, 0},
};

static const lunatik_namespace_t luafoo_namespaces[] = {
	{"flags", luafoo_flags},
	{NULL, NULL},
};

LUNATIK_NEWLIB(foo, luafoo_lib, &luafoo_class, luafoo_namespaces);
```

---

## Memory

### lunatik\_malloc
```C
void *lunatik_malloc(lua_State *L, size_t size);
```
Allocates `size` bytes using the Lua allocator. Returns `NULL` on failure.

### lunatik\_realloc
```C
void *lunatik_realloc(lua_State *L, void *ptr, size_t size);
```
Reallocates `ptr` to `size` bytes using the Lua allocator.

### lunatik\_free
```C
void lunatik_free(void *ptr);
```
Frees memory allocated by `lunatik_malloc` or `lunatik_realloc`. Equivalent to `kfree`.

