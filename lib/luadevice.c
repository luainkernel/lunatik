/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Low-level Lua interface for creating Linux character device drivers.
*
* This module allows Lua scripts to implement character device drivers
* by providing callback functions for standard file operations like
* `open`, `read`, `write`, and `release`.
*
* A file operation runs on the task performing it, in process context, so its
* callback may sleep. It runs under the lock of the runtime that made the device,
* so one the runtime's own code performs, a
* callback or a `thread` body opening the node it made, fails with `EDEADLK`:
* it would wait on the lock its task holds. An `open`, `read` or `write`
* callback fails its operation with an errno by returning it negated, as
* `-errno.EBUSY` does with `linux.errno`. A callback that raises, or that
* returns a length or an offset that is not an integer, or an errno that is not
* one, `invalid errno` in the log, fails its operation with `ECANCELED`, and the
* error goes to the kernel log.
*
* @module device
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/fs.h>
#include <linux/printk.h>
#include <linux/string.h>
#include <linux/device.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/list.h>
#include <linux/mutex.h>
#include <linux/kref.h>

#include <lunatik.h>

static struct class *luadevice_devclass;

/***
* Represents a character device implemented in Lua.
* This is a userdata object returned by `device.new()`. It encapsulates
* the necessary kernel structures (`struct cdev`, `dev_t`) to manage a
* character device, linking file operations to Lua callback functions.
* @type device
*/
typedef struct luadevice_s {
	struct list_head entry;
	struct kref kref;
	lunatik_object_t *runtime;
	struct cdev *cdev;
	dev_t devt;
	umode_t mode;
} luadevice_t;



static DEFINE_MUTEX(luadevice_mutex);
static LIST_HEAD(luadevice_list);

#define luadevice_lock()		mutex_lock(&luadevice_mutex)
#define luadevice_unlock()		mutex_unlock(&luadevice_mutex)
#define luadevice_foreach(luadev)	list_for_each_entry((luadev), &luadevice_list, entry)

static inline void luadevice_listadd(luadevice_t *luadev)
{
	luadevice_lock();
	list_add_tail(&luadev->entry, &luadevice_list);
	luadevice_unlock();
}

static inline void luadevice_listdel(luadevice_t *luadev)
{
	luadevice_lock();
	list_del_init(&luadev->entry);
	luadevice_unlock();
}

static noinline void luadevice_free(struct kref *kref) /* tests/device counts frees at this symbol */
{
	luadevice_t *luadev = container_of(kref, luadevice_t, kref);

	if (luadev->runtime) /* NULL if setruntime errored in init */
		lunatik_putobject(luadev->runtime);
	lunatik_free(luadev);
}

#define luadevice_put(luadev)	kref_put(&(luadev)->kref, luadevice_free)

static inline luadevice_t *luadevice_find(struct cdev *cdev)
{
	luadevice_t *luadev, *found = NULL;
	luadevice_lock();
	luadevice_foreach(luadev)
		if (luadev->cdev == cdev) {
			found = luadev;
			kref_get(&found->kref);
			break;
		}
	luadevice_unlock();
	return found;
}

static int luadevice_new(lua_State *L);

typedef struct luadevice_ctx_s {
	struct file *f;
	const char *fop;
	char *buf;
	size_t len;
	loff_t *off;
	ssize_t ret;
} luadevice_ctx_t;

#define luadevice_fromfile(f)	((luadevice_t *)(f)->private_data)

static lua_Integer luadevice_optinteger(lua_State *L, int ix, const char *name, lua_Integer def)
{
	lua_Integer n;
	int isnum;

	if (lua_isnoneornil(L, ix))
		return def;
	n = lua_tointegerx(L, ix, &isnum);
	if (!isnum)
		luaL_error(L, "%s is not an integer", name);
	return n;
}

static int luadevice_fop(lua_State *L, luadevice_ctx_t *ctx, int nargs, int nresults)
{
	int base = lua_gettop(L) - nargs;

	if (lunatik_getregistry(L, luadevice_fromfile(ctx->f)) != LUA_TTABLE) /* stopped */
		return -ENXIO;

	lunatik_optcfunction(L, -1, ctx->fop, lunatik_nop);

	lua_insert(L, base + 1); /* fop */
	lua_insert(L, base + 2); /* driver */
	lua_call(L, nargs + 1, nresults); /* fop(driver, arg1, ...) */
	return 0;
}

static int luadevice_doopen(lua_State *L)
{
	luadevice_ctx_t *ctx = lua_touserdata(L, 1);

	lua_newtable(L); /* file */
	lua_pushvalue(L, -1);
	if ((ctx->ret = luadevice_fop(L, ctx, 1, 1)) == 0 && (ctx->ret = lunatik_opterrno(L, -1)) == 0)
		lunatik_register(L, -2, ctx->f); /* a failed open gets no release to drop it */
	return 0;
}

static int luadevice_doread(lua_State *L)
{
	luadevice_ctx_t *ctx = lua_touserdata(L, 1);
	size_t llen;
	const char *lbuf;
	loff_t off;

	lua_pushinteger(L, ctx->len);
	lua_pushinteger(L, *ctx->off);
	lunatik_getregistry(L, ctx->f); /* file */
	if ((ctx->ret = luadevice_fop(L, ctx, 3, 2)) != 0)
		return 0;

	if (lua_type(L, -2) == LUA_TNUMBER) {
		ctx->ret = lunatik_opterrno(L, -2);
		return 0;
	}

	lbuf = lua_tolstring(L, -2, &llen);
	llen = min(ctx->len, llen);
	off = (loff_t)luadevice_optinteger(L, -1, "offset", *ctx->off + llen);
	if (copy_to_user(ctx->buf, lbuf, llen) != 0) {
		ctx->ret = -EFAULT;
		return 0;
	}

	*ctx->off = off;
	ctx->ret = (ssize_t)llen;
	return 0;
}

static int luadevice_dowrite(lua_State *L)
{
	luadevice_ctx_t *ctx = lua_touserdata(L, 1);
	luaL_Buffer B;
	lua_Integer n;
	size_t llen;
	char *lbuf;

	lbuf = luaL_buffinitsize(L, &B, ctx->len);

	if (copy_from_user(lbuf, ctx->buf, ctx->len) != 0) {
		luaL_pushresultsize(&B, 0);
		ctx->ret = -EFAULT;
		return 0;
	}

	luaL_pushresultsize(&B, ctx->len);
	lua_pushinteger(L, *ctx->off);
	lunatik_getregistry(L, ctx->f); /* file */
	if ((ctx->ret = luadevice_fop(L, ctx, 3, 2)) != 0)
		return 0;

	if ((n = luadevice_optinteger(L, -2, "length", ctx->len)) < 0) {
		ctx->ret = lunatik_opterrno(L, -2);
		return 0;
	}

	llen = min(ctx->len, (size_t)n);
	*ctx->off = (loff_t)luadevice_optinteger(L, -1, "offset", *ctx->off + llen);
	ctx->ret = (ssize_t)llen;
	return 0;
}

static int luadevice_dorelease(lua_State *L)
{
	luadevice_ctx_t *ctx = lua_touserdata(L, 1);

	lunatik_getregistry(L, ctx->f); /* file */
	lunatik_unregister(L, ctx->f); /* before the callback, which may raise */
	ctx->ret = luadevice_fop(L, ctx, 1, 0);
	return 0;
}

#define luadevice_run(op, ret, ctx)							\
do {											\
	(ctx)->fop = #op;								\
	lunatik_run(luadevice_fromfile((ctx)->f)->runtime, lunatik_catch,		\
		ret, luadevice_do##op, ctx, (ctx)->fop);				\
	if (ret == 0)									\
		ret = (ctx)->ret;							\
} while (0)

static int luadevice_fop_open(struct inode *inode, struct file *f)
{
	luadevice_ctx_t ctx = {.f = f};
	luadevice_t *luadev;
	int ret;

	if ((luadev = luadevice_find(inode->i_cdev)) == NULL)
		return -ENXIO;

	f->private_data = luadev;
	luadevice_run(open, ret, &ctx);
	if (ret != 0)
		luadevice_put(luadev);
	return ret;
}

static ssize_t luadevice_fop_read(struct file *f, char *buf, size_t len, loff_t *off)
{
	luadevice_ctx_t ctx = {.f = f, .buf = buf, .len = len, .off = off};
	ssize_t ret;

	luadevice_run(read, ret, &ctx);
	return ret;
}

static ssize_t luadevice_fop_write(struct file *f, const char *buf, size_t len, loff_t* off)
{
	luadevice_ctx_t ctx = {.f = f, .buf = (char *)buf, .len = len, .off = off};
	ssize_t ret;

	luadevice_run(write, ret, &ctx);
	return ret;
}

static int luadevice_fop_release(struct inode *inode, struct file *f)
{
	luadevice_ctx_t ctx = {.f = f};
	int ret;

	luadevice_run(release, ret, &ctx);
	luadevice_put(luadevice_fromfile(f));
	return ret;
}

static struct file_operations luadevice_fops =
{
	.owner = THIS_MODULE,
	.open = luadevice_fop_open,
	.read = luadevice_fop_read,
	.write = luadevice_fop_write,
	.release = luadevice_fop_release
};

static void luadevice_delete(luadevice_t *luadev)
{
	luadevice_listdel(luadev); /* first: luadevice_find reads the cdev cleared next */
	if (luadev->cdev != NULL) {
		cdev_del(luadev->cdev);
		luadev->cdev = NULL;
	}

	if (luadev->devt != 0) {
		device_destroy(luadevice_devclass, luadev->devt);
		unregister_chrdev_region(luadev->devt, 1);
		luadev->devt = 0;
	}
}

static void luadevice_release(void *private)
{
	luadevice_t *luadev = (luadevice_t *)private;

	/* device might have never been stopped */
	luadevice_delete(luadev);
	luadevice_put(luadev);
}

/***
* Stops a character device driver and removes it from the system.
* This method is called on a device object returned by `device.new()`: the
* device file (`/dev/<name>`) and its region go with it. Without `stop`, the
* device lives until its runtime stops, since `device.new` keeps the object for
* the runtime. A file still open on the device gets ENXIO from read and write
* until it is closed. A to-be-closed variable holding the device stops it the
* same way.
* @function stop
* @treturn nil Does not return any value to Lua.
* @raise if the argument is not a device.
* @usage
*   -- Assuming 'dev' is a device object:
*   dev:stop()
* @see device.new
*/
static const lunatik_class_t luadevice_class;

static int luadevice_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luadevice_class);
	luadevice_t *luadev = (luadevice_t *)object->private;

	lunatik_lock(object);
	luadevice_delete(luadev);
	lunatik_unlock(object);

	lunatik_unregisterobject(L, object);
	return 0;
}

/***
* Creates and installs a new character device driver in the system.
* This function binds a Lua table (the `driver` table) to a new
* character device file (`/dev/<name>`), allowing Lua functions
* to handle file operations on that device.
*
* @function new
* @tparam table driver A table defining the device driver's properties and callbacks.
*   It **must** contain the field:
*
*   - `name` (string): The name of the device. This name will be used to create
*     the device file `/dev/<name>`.
*
*   It **might** optionally contain the following fields (callback functions),
*   each of which receives, after its own arguments, `file`: a table private to
*   one open of the device, the same in every callback that open reaches from
*   its `open` to its `release`, where the driver keeps what belongs to that
*   open.
*
*   - `open` (function): Callback for the `open(2)` system call.
*     Signature: `function(driver_table, file) -> [errno]`. Returning nothing or zero opens
*     the file, and returning a negative errno, `-errno.EBUSY` say, fails the open with it.
*   - `read` (function): Callback for the `read(2)` system call.
*     Signature: `function(driver_table, length, offset, file) -> string [, updated_offset]`.
*     Receives the driver table, the requested read length (integer), and the current
*     file offset (integer). Should return the data as a string and optionally the
*     updated file offset (integer), or a negative errno, `-errno.EAGAIN` say, which
*     fails the read with it. If `updated_offset` is not returned, the offset
*     is advanced by the length of the returned string (or the requested length if
*     the string is longer).
*   - `write` (function): Callback for the `write(2)` system call.
*     Signature: `function(driver_table, buffer_string, offset, file) -> [written_length] [, updated_offset]`.
*     Receives the driver table, the data to write as a string, and the current file
*     offset (integer). May return the number of bytes successfully written (integer),
*     or a negative errno, `-errno.ENOSPC` say, which fails the write with it,
*     and optionally the updated file offset (integer). If `written_length` is not
*     returned, it's assumed all provided data was written. If `updated_offset` is
*     not returned, the offset is advanced by the `written_length`.
*   - `release` (function): runs when the last reference to an open file is closed,
*     the final close(2). Signature: `function(driver_table, file)`.
*     Expected to return nothing.
*
*   A read returns end of file when its callback returns an empty string, `nil` or zero.
*
*   It **might** also contain the field:
*
*   - `mode` (integer): Optional permission bits of the device file, within `S_IALLUGO`:
*     the file type is the kernel's, a character device. Use constants from `linux.stat`
*     (e.g., `stat.IRUGO`).
* @treturn device the device, which `device.new` keeps for its runtime: dropping it
*   stops nothing, and the device stays until `stop` or the end of the runtime.
* @raise Error if the device cannot be allocated or registered in the kernel,
*   if the `name` field is missing or not a string, or if called from a percpu runtime;
*   `bad field 'mode' (number expected, got <type>)` if `mode` is present and not a number;
*   `bad field 'mode' (out of bounds)` if it is negative or past `S_IALLUGO`, as a mode that
*   carries a file type is;
*   `'device': process-context class in interrupt-context runtime` in a softirq or
*   hardirq runtime (run it in process context, the default of `lunatik run`);
*   `not allowed while the runtime closes` from a finalizer that runs at its close.
* @usage
*   local device = require("device")
*   local stat   = require("linux.stat")
*
*   local function read(drv, len, off)
*     local data = "Hello from " .. drv.name .. "!\n"
*     return data:sub(off + 1, off + len)
*   end
*
*   local my_driver = {
*     name = "my_lua_device",
*     mode = stat.IRUGO, -- Read-only for all
*     read = read,
*   }
*   local dev_obj = device.new(my_driver)
*   -- To remove it: dev_obj:stop(), or stop the runtime.
* @within device
*/
static const luaL_Reg luadevice_lib[] = {
	{"new", luadevice_new},
	{NULL, NULL}
};

static const luaL_Reg luadevice_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", luadevice_stop},
	{"stop", luadevice_stop},
	{NULL, NULL}
};

static const lunatik_class_t luadevice_class = {
	.name = "device",
	.methods = luadevice_mt,
	.release = luadevice_release,
	.opt = LUNATIK_OPT_SINGLE | LUNATIK_OPT_EXTERNAL,
	.owner = THIS_MODULE,
};

static int luadevice_new(lua_State *L)
{
	lunatik_object_t *object;
	luadevice_t *luadev;
	struct device *device;
	const char *name;

	lunatik_checkpercpu(L);
	luaL_checktype(L, 1, LUA_TTABLE); /* driver */

	lunatik_checkfield(L, 1, "name", LUA_TSTRING);
	name = lua_tostring(L, -1);

	object = lunatik_newobject(L, &luadevice_class, 0, LUNATIK_OPT_NONE);
	luadev = (luadevice_t *)lunatik_checkzalloc(L, sizeof(luadevice_t));
	kref_init(&luadev->kref);
	INIT_LIST_HEAD(&luadev->entry); /* a raise before the device is listed deletes it unlisted */
	object->private = luadev;
	lunatik_optinteger(L, 1, luadev, mode, 0, S_IALLUGO, 0);

	lunatik_setruntime(L, device, luadev);
	lunatik_getobject(luadev->runtime);

	lunatik_try(L, alloc_chrdev_region, &luadev->devt, 0, 1, name);

	luadev->cdev = lunatik_checknull(L, cdev_alloc());
	luadev->cdev->ops = &luadevice_fops;
	lunatik_try(L, cdev_add, luadev->cdev, luadev->devt, 1);

	luadevice_listadd(luadev);
	lunatik_registerobject(L, 1, object); /* driver */

	device = device_create(luadevice_devclass, NULL, luadev->devt, luadev, name); /* calls devnode */
	if (IS_ERR(device)) {
		lunatik_unregisterobject(L, object);
		lunatik_throw(L, PTR_ERR(device));
	}
	lua_remove(L, -2); /* remove name */

	return 1; /* object */
}

LUNATIK_CLASSES(device, &luadevice_class);
LUNATIK_NEWLIB(device, luadevice_lib, luadevice_classes);

static char *luadevice_devnode(const struct device *dev, umode_t *mode)
{
	luadevice_t *luadev = (luadevice_t *)dev_get_drvdata(dev);

	if (mode && luadev->mode)
		*mode = luadev->mode;
	return NULL;
}

static int __init luadevice_init(void)
{
	luadevice_devclass = class_create("luadevice");
	if (IS_ERR(luadevice_devclass)) {
		pr_err("failed to create luadevice class\n");
		return PTR_ERR(luadevice_devclass);
	}
	luadevice_devclass->devnode = luadevice_devnode;
	return 0;
}

static void __exit luadevice_exit(void)
{
	class_destroy(luadevice_devclass);
}

module_init(luadevice_init);
module_exit(luadevice_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

