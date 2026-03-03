# Lunatik C API

```C
#include <lunatik.h>
```

## lunatik\_runtime
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
flag for allocating new memory later on on
[lunatik\_run()](https://github.com/luainkernel/lunatik#lunatik_run) calls.
Otherwise, it will use a [spinlock](https://docs.kernel.org/locking/locktypes.html#raw-spinlock-t-and-spinlock-t) and [GFP\_ATOMIC](https://www.kernel.org/doc/html/latest/core-api/memory-allocation.html).
_lunatik\_runtime()_ opens the Lua standard libraries
[present on Lunatik](https://github.com/luainkernel/lunatik#c-api).
If successful, _lunatik\_runtime()_ sets the address pointed by `pruntime` and
[Lua's extra space](https://www.lua.org/manual/5.5/manual.html#lua_getextraspace)
with a pointer for the new created `runtime` environment,
sets the _reference counter_ to `1` and then returns `0`.
Otherwise, it returns `-ENOMEM`, if insufficient memory is available;
or `-EINVAL`, if it fails to load or run the `script`.

### Example
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

## lunatik\_stop
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

## lunatik\_run
```C
void lunatik_run(lunatik_object_t *runtime, <inttype> (*handler)(...), <inttype> &ret, ...);
```
_lunatik\_run()_ locks the `runtime` environment and calls the `handler`
passing the associated Lua state as the first argument followed by the variadic arguments.
If the Lua state has been closed, `ret` is set with `-ENXIO`;
otherwise, `ret` is set with the result of `handler(L, ...)` call.
Then, it restores the Lua stack and unlocks the `runtime` environment.
It is defined as a macro.

### Example
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

## lunatik\_newobject
```C
lunatik_object_t *lunatik_newobject(lua_State *L, const lunatik_class_t *class, size_t size, bool shared);
```
_lunatik\_newobject()_ allocates a new Lunatik object and pushes a userdata
containing a pointer to the object onto the Lua stack.
If `shared` is _true_, the object will use the monitored metatable for safe
access Lunatik runtimes. This requires `class->shared = true;` otherwise, it raises a
Lua error.
- If `class->sleep` is _true_, it uses a mutex and `GFP_KERNEL`
- If `class->sleep` is _false_, it uses a spinlock and `GFP_ATOMIC`

It allocates size bytes for the object's private data, unless `class->pointer` is true.

## lunatik\_createobject
```C
lunatik_object_t *lunatik_createobject(const lunatik_class_t *class, size_t size, bool sleep, bool shared);
```
_lunatik\_createobject()_ creates a Lunatik object independently of any Lua
state. This is intended for objects created in C context that may be shared
with Lua runtimes later.

It allocates memory with `GFP_KERNEL` if `sleep` is _true_, or `GFP_ATOMIC` otherwise.
It returns a pointer to the `lunatik_object_t` on success, or _NULL_ if memory
allocation fails and _ERR_PTR(-EINVAL)_ if the class is not sharable but API is called with _true_ as `shared`

## lunatik\_getobject
```C
void lunatik_getobject(lunatik_object_t *object);
```
_lunatik\_getobject()_ increments the
[reference counter](https://www.kernel.org/doc/Documentation/kref.txt)
of this `object` (e.g., `runtime` environment).

## lunatik\_put
```C
int lunatik_putobject(lunatik_object_t *object);
```
_lunatik\_putobject()_ decrements the
[reference counter](https://www.kernel.org/doc/Documentation/kref.txt)
of this `object` (e.g., `runtime` environment).
If the `object` has been released, it returns `1`;
otherwise, it returns `0`.

## lunatik\_toruntime
```C
lunatik_object_t *lunatik_toruntime(lua_State *L);
```
_lunatik\_toruntime()_ returns the `runtime` environment referenced by the `L`'s
[extra space](https://www.lua.org/manual/5.5/manual.html#lua_getextraspace).

