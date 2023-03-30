/*
* Copyright (c) 2023 ring-0 Ltda.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/printk.h>
#include <linux/string.h>
#include <linux/device.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/list.h>
#include <linux/mutex.h>
#include <linux/kref.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

static struct class *luadevice_class;

typedef struct luadevice_s {
	struct cdev *cdev;
	dev_t devt;
	int ud;
} luadevice_t;

typedef struct luadevice_ctx_s {
	struct list_head entry;
	struct kref kref;
	lunatik_runtime_t *runtime;
	luadevice_t *luadev;
} luadevice_ctx_t;

static DEFINE_MUTEX(luadevice_ctxmutex);
static LIST_HEAD(luadevice_ctxlist);

#define luadevice_ctxlock()		mutex_lock(&luadevice_ctxmutex)
#define luadevice_ctxunlock()		mutex_unlock(&luadevice_ctxmutex)
#define luadevice_ctxforeach(ctx)	list_for_each_entry(ctx, &luadevice_ctxlist, entry)

static void luadevice_ctxfree(struct kref *kref)
{
	luadevice_ctx_t *ctx = container_of(kref, luadevice_ctx_t, kref);
	kfree(ctx);
}

#define luadevice_ctxref(ctx)	(&(ctx)->kref)
#define luadevice_ctxinit(ctx)	kref_init(luadevice_ctxref(ctx))
#define luadevice_ctxget(ctx)	kref_get(luadevice_ctxref(ctx))
#define luadevice_ctxput(ctx)	kref_put(luadevice_ctxref(ctx), luadevice_ctxfree)

static inline void luadevice_ctxadd(luadevice_ctx_t *ctx)
{
	luadevice_ctxlock();
	list_add_tail(&ctx->entry, &luadevice_ctxlist);
	luadevice_ctxunlock();
}

static inline void luadevice_ctxdel(luadevice_ctx_t *ctx)
{
	luadevice_ctxlock();
	list_del(&ctx->entry);
	luadevice_ctxunlock();
}

static inline luadevice_ctx_t *luadevice_ctxnew(lua_State *L, luadevice_t *luadev)
{
	luadevice_ctx_t *ctx;
	if ((ctx = (luadevice_ctx_t *)kzalloc(sizeof(luadevice_ctx_t), GFP_KERNEL)) == NULL)
		return NULL;
	ctx->luadev = luadev;
	ctx->runtime = lunatik_toruntime(L);
	luadevice_ctxinit(ctx);
	luadevice_ctxadd(ctx);
	return ctx;
}

static luadevice_ctx_t *luadevice_ctxfind(dev_t devt)
{
	luadevice_ctx_t *ctx = NULL;

	luadevice_ctxlock();
	luadevice_ctxforeach(ctx) {
		luadevice_t *luadev = ctx->luadev;
		if (luadev == NULL)
			pr_err("lost context: %p\n", ctx);
		else if (luadev->devt == devt)
			break;
	}
	luadevice_ctxunlock();
	return ctx;
}

#define DEVICE_MT	"device"

#define luadevice_userdata(L, ud)	(lua_rawgeti(L, LUA_REGISTRYINDEX, ud) != LUA_TUSERDATA)
#define luadevice_driver(L, ix)		(lua_getiuservalue(L, ix, 1) != LUA_TTABLE)

static inline int luadevice_getdriver(lua_State *L, int ud)
{
	int base = lua_gettop(L);
	int ret = luadevice_userdata(L, ud) || luadevice_driver(L, -1);
	lua_replace(L, ++base);
	lua_settop(L, base);
	return ret;
}

static int luadevice_fop(lua_State *L, int ud, const char *fop, int nargs, int nresults)
{
	int base = lua_gettop(L) - nargs;
	int ret = -ENXIO;

	if (luadevice_getdriver(L, ud) != 0) {
		pr_err("%s: couln't find driver\n", fop);
		goto err;
	}

	if (lua_getfield(L, -1, fop) != LUA_TFUNCTION) {
		lua_getfield(L, -2, "name");
		pr_err("%s: operation isn't defined for /dev/%s\n", fop, lua_tostring(L, -1));
		goto err;
	}

	lua_insert(L, base + 1); /* fop */
	lua_insert(L, base + 2); /* driver */

	if (lua_pcall(L, nargs + 1, nresults, 0) != LUA_OK) { /* fop(driver, arg1, ...) */
		pr_err("%s: %s\n", lua_tostring(L, -1), fop);
		ret = -ECANCELED;
		goto err;
	}
	return 0;
err:
	lua_settop(L, base); /* pop everything, including args */
	return ret;
}

static int luadevice_doopen(lua_State *L, int ud)
{
	int ret;

	if ((ret = luadevice_fop(L, ud, "open", 0, 1)) != 0)
		return ret;
	return (int)lua_tointeger(L, -1);
}

static ssize_t luadevice_doread(lua_State *L, int ud, char *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	size_t llen;
	const char *lbuf;

	lua_pushinteger(L, len);
	lua_pushinteger(L, *off);
	if ((ret = luadevice_fop(L, ud, "read", 2, 2)) != 0)
		return ret;

	lbuf = lua_tolstring(L, -2, &llen);
	llen = min(len, llen);
	if (copy_to_user(buf, lbuf, llen) != 0)
		return -EFAULT;

	*off = (loff_t)luaL_optinteger(L, -1, *off + llen);
	return (ssize_t)llen;
}

static ssize_t luadevice_dowrite(lua_State *L, int ud, const char *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	luaL_Buffer B;
	size_t llen;
	char *lbuf;

	lbuf = luaL_buffinitsize(L, &B, len);

	if (copy_from_user(lbuf, buf, len) != 0) {
		luaL_pushresultsize(&B, 0);
		return -EFAULT;
	}

	luaL_pushresultsize(&B, len);
	lua_pushinteger(L, *off);
	if ((ret = luadevice_fop(L, ud, "write", 2, 2)) != 0)
		return ret;

	llen = (size_t)luaL_optinteger(L, -2, len);
	llen = min(len, llen);
	*off = (loff_t)luaL_optinteger(L, -1, *off + llen);
	return (ssize_t)llen;
}

static int luadevice_dorelease(lua_State *L, int ud)
{
	int ret;

	if ((ret = luadevice_fop(L, ud, "release", 0, 1)) != 0)
		return ret;
	return (int)lua_tointeger(L, -1);
}

#define luadevice_ctxfile(f)	((luadevice_ctx_t *)f->private_data)
#define luadevice_run(handler, ret, f, ...)					\
		lunatik_run(luadevice_ctxfile(f)->runtime, handler,		\
			ret, luadevice_ctxfile(f)->luadev->ud, ## __VA_ARGS__)

static int luadevice_open(struct inode *inode, struct file *f)
{
	luadevice_ctx_t *ctx;
	int ret;

	if ((ctx = luadevice_ctxfind(inode->i_rdev)) == NULL)
		return -ENXIO;

	luadevice_ctxget(ctx);
	lunatik_get(ctx->runtime);
	f->private_data = ctx;
	luadevice_run(luadevice_doopen, ret, f);
	return ret;
}

static ssize_t luadevice_read(struct file *f, char *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	luadevice_run(luadevice_doread, ret, f, buf, len, off);
	return ret;
}

static ssize_t luadevice_write(struct file *f, const char *buf, size_t len, loff_t* off)
{
	ssize_t ret;
	luadevice_run(luadevice_dowrite, ret, f, buf, len, off);
	return ret;
}

static int luadevice_release(struct inode *inode, struct file *f)
{
	luadevice_ctx_t *ctx;
	int ret;

	luadevice_run(luadevice_dorelease, ret, f);
	ctx = luadevice_ctxfile(f);
	lunatik_put(ctx->runtime);
	luadevice_ctxput(ctx);
	return ret;
}

static struct file_operations luadevice_fops =
{
	.owner = THIS_MODULE,
	.open = luadevice_open,
	.read = luadevice_read,
	.write = luadevice_write,
	.release = luadevice_release
};

static int luadevice_new(lua_State *L)
{
	luadevice_ctx_t *ctx;
	luadevice_t *luadev;
	struct device *device;
	const char *name;
	int tname;
	int ret;

	luaL_checktype(L, 1, LUA_TTABLE); /* driver */
	if ((tname = lua_getfield(L, -1, "name")) != LUA_TSTRING) /* driver.name */
		luaL_error(L, "bad field 'name' (string expected, got %s)", lua_typename(L, tname));
	name = lua_tostring(L, -1);

	luadev = (luadevice_t *)lua_newuserdatauv(L, sizeof(luadevice_t), 1);
	luadev->ud = LUA_NOREF;

	if ((ctx = luadevice_ctxnew(L, luadev)) == NULL)
		luaL_error(L, "failed to allocate device context");

	luaL_setmetatable(L, DEVICE_MT); /* __gc() is set for cleanup */
	lua_pushvalue(L, 1);  /* push driver */
	lua_setiuservalue(L, -2, 1); /* pops driver */

	if ((ret = alloc_chrdev_region(&luadev->devt, 0, 1, name) != 0))
		luaL_error(L, "failed to allocate char device region (%d)", ret);

	if ((luadev->cdev = cdev_alloc()) == NULL)
		luaL_error(L, "failed to allocate cdev");
	luadev->cdev->ops = &luadevice_fops;
	if ((ret = cdev_add(luadev->cdev, luadev->devt, 1)) != 0)
		luaL_error(L, "failed to add cdev (%d)", ret);

	lua_pushvalue(L, -1);  /* push userdata */
	luadev->ud = luaL_ref(L, LUA_REGISTRYINDEX); /* pops userdata */

	lua_pushvalue(L, 1);  /* push driver */
	device = device_create(luadevice_class, NULL, luadev->devt, ctx, name); /* calls devnode */
	if (IS_ERR(device))
		luaL_error(L, "failed to create a new device (%d)", PTR_ERR(device));
	lua_pop(L, 1); /* pop driver */
	lua_remove(L, -2); /* remove driver.name */

	return 1; /* userdata */
}

static int luadevice_delete(lua_State *L)
{
	luadevice_ctx_t *ctx;
	luadevice_t *luadev;

	luadev = (luadevice_t *)luaL_checkudata(L, 1, DEVICE_MT);

	if (luadev->cdev != NULL)
		cdev_del(luadev->cdev);

	if (luadev->devt != 0) {
		device_destroy(luadevice_class, luadev->devt);
		unregister_chrdev_region(luadev->devt, 1);
	}

	if ((ctx = luadevice_ctxfind(luadev->devt)) != NULL) {
		ctx->luadev = NULL;
		luadevice_ctxdel(ctx);
		luadevice_ctxput(ctx);
	}

	luaL_unref(L, LUA_REGISTRYINDEX, luadev->ud);
	return 0;
}

static int luadevice_set(lua_State *L)
{
	luadevice_t *luadev;

	luadev = (luadevice_t *)luaL_checkudata(L, 1, DEVICE_MT);
	if (luadevice_driver(L, 1) != 0)
		luaL_error(L, "couln't find driver");

	lua_replace(L, 1); /* driver -> userdata */
	lua_settable(L, 1); /* driver[key] = value */
	return 0;
}

static const luaL_Reg device_lib[] = {
	{"new", luadevice_new},
	{"delete", luadevice_delete},
	{"set", luadevice_set},
	{NULL, NULL}
};

static const luaL_Reg device_mt[] = {
	{"__gc", luadevice_delete},
	{"__close", luadevice_delete},
	{"__newindex", luadevice_set},
	{"delete", luadevice_delete},
	{"set", luadevice_set},
	{NULL, NULL}
};

LUNATIK_NEWLIB(device, DEVICE_MT, true);

static char *luadevice_devnode(struct device *dev, umode_t *mode)
{
	lua_State *L;
	luadevice_ctx_t *ctx;
	luadevice_t *luadev;
	int base;

	if (!mode)
		goto out;

	ctx = (luadevice_ctx_t *)dev_get_drvdata(dev);
	luadev = ctx->luadev;
	L = ctx->runtime->L;

	base = lua_gettop(L);
	if (luadevice_getdriver(L, luadev->ud) == 0 && lua_getfield(L, -1, "mode") == LUA_TNUMBER)
		*mode = (umode_t)lua_tointeger(L, -1);
	lua_settop(L, base);
out:
	return NULL;
}

static int __init luadevice_init(void)
{
	luadevice_class = class_create(THIS_MODULE, "luadevice");
	if (IS_ERR(luadevice_class)) {
		pr_err("failed to create luadevice class\n");
		return PTR_ERR(luadevice_class);
	}
	luadevice_class->devnode = luadevice_devnode;
	return 0;
}

static void __exit luadevice_exit(void)
{
	class_destroy(luadevice_class);
}

module_init(luadevice_init);
module_exit(luadevice_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

