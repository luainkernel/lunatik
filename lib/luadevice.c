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

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/printk.h>
#include <linux/string.h>
#include <linux/device.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

#define LUADEVICE_MT	"device"

static struct class *luadevice_class;

typedef struct luadevice {
	dev_t major;
	struct cdev cdev;
	unsigned int count;
	lua_State *L;
	int ud;
} luadevice_t;

#define LUADEVICE_DEVLISTUV	(1)
#define luadevice_getminor(L, ud, minor)						\
	((lua_rawgeti(L, LUA_REGISTRYINDEX, ud) != LUA_TUSERDATA) || /* userdata */	\
	 (lua_getiuservalue(L, -1, LUADEVICE_DEVLISTUV) != LUA_TTABLE) || /* devlist */	\
	 (lua_geti(L, -1, minor) != LUA_TTABLE)) /* minor */

static int luadevice_fop(lua_State *L, int ud, unsigned int minor,
	const char *fop, int nargs, int nresults)
{
	int bottom;

	bottom = lua_gettop(L) - nargs + 1;

	if (luadevice_getminor(L, ud, minor) != 0 || (lua_getfield(L, -1, fop) != LUA_TFUNCTION)) {
		/* TODO: improve error handling (e.g., logging device name and minor) */
		pr_err("'%s' operation isn't defined\n", fop);
		lua_settop(L, bottom - 1); /* pop everything, including args */
		return -ENXIO;
	}

	lua_insert(L, bottom); /* fop */
	lua_insert(L, bottom + 1); /* minor */
	lua_pop(L, 2); /* userdata, devlist */

	if (lua_pcall(L, nargs + 1, nresults, 0) != LUA_OK) {
		/* TODO: improve this error message */
		pr_err("runtime error: '%s'\n", lua_tostring(L, -1));
		lua_pop(L, 1); /* error */
		return -ECANCELED;
	}
	return 0;
}

static int luadevice_doopen(lua_State *L, int ud, unsigned int minor)
{
	int ret;

	if ((ret = luadevice_fop(L, ud, minor, "open", 0, 1)) != 0)
		return ret;
	return (int)lua_tointeger(L, -1);
}

static ssize_t luadevice_doread(lua_State *L, int ud, unsigned int minor,
	char *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	size_t llen;
	const char *lbuf;

	/* TODO: use luamemory here instead of string */
	lua_pushinteger(L, len);
	lua_pushinteger(L, *off);
	if ((ret = luadevice_fop(L, ud, minor, "read", 2, 2)) != 0)
		return ret;

	lbuf = lua_tolstring(L, -2, &llen);
	llen = min(len, llen);
	if (copy_to_user(buf, lbuf, llen) != 0)
		return -EFAULT;

	*off = (loff_t)luaL_optinteger(L, -1, *off + llen);
	return (ssize_t)llen;
}

static ssize_t luadevice_dowrite(lua_State *L, int ud, unsigned int minor,
	const char *buf, size_t len, loff_t *off)
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
	if ((ret = luadevice_fop(L, ud, minor, "write", 2, 2)) != 0)
		return ret;

	llen = (size_t)luaL_optinteger(L, -2, len);
	llen = min(len, llen);
	*off = (loff_t)luaL_optinteger(L, -1, *off + llen);
	return (ssize_t)llen;
}

static int luadevice_dorelease(lua_State *L, int ud, unsigned int minor)
{
	int ret;

	if ((ret = luadevice_fop(L, ud, minor, "release", 0, 1)) != 0)
		return ret;
	return (int)lua_tointeger(L, -1);
}

#define luadevice_minor(f)	(iminor(file_inode(f)))
#define luadevice_data(f)	((luadevice_t *)f->private_data)
#define luadevice_run(handler, ret, f, ...)			\
	lunatik_run(luadevice_data(f)->L, handler, ret,		\
		luadevice_data(f)->ud, luadevice_minor(f),	\
		## __VA_ARGS__)

static int luadevice_open(struct inode *inode, struct file *f)
{
	int ret;
	luadevice_t *luadev;

	luadev = (luadevice_t *)container_of(inode->i_cdev, luadevice_t, cdev);
	f->private_data = luadev;
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

static int luadevice_release(struct inode *i, struct file *f)
{
	int ret;
	luadevice_run(luadevice_dorelease, ret, f);
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

#define LUADEVICE_DEV(luadev, i)	(MKDEV(MAJOR(luadev->major), MINOR(luadev->major) + i))
#define LUADEVICE_FIRSTMINOR		(1) /* 1-based indexing */

static void luadevice_createminors(luadevice_t *luadev, const char* name, int devlist)
{
	int base, i;

	base = lua_gettop(luadev->L); /* save stack */

	for (i = 0; i < luadev->count; i++) {
		struct device *device;
		const char *minorname;

		lua_geti(luadev->L, devlist, LUADEVICE_FIRSTMINOR + i); /* minor */
		lua_getfield(luadev->L, -1, "name"); /* minor.name */
		minorname = lua_tostring(luadev->L, -1);

		device = device_create(luadevice_class, NULL, LUADEVICE_DEV(luadev, i), luadev,
			minorname != NULL ? minorname : lua_pushfstring(luadev->L, "%s%d", name, i));
		if (IS_ERR(device))
			luaL_error(luadev->L, "failed to create a new device (%d)", PTR_ERR(device));

		lua_settop(luadev->L, base); /* restore stack */
	}
}

static void luadevice_destroyminors(luadevice_t *luadev)
{
	int i;

	for (i = 0; i < luadev->count; i++)
		device_destroy(luadevice_class, LUADEVICE_DEV(luadev, i));
}

static int luadevice_create(lua_State *L)
{
	luadevice_t *luadev;
	const char *name;
	int ret;

	name = luaL_checkstring(L, 1);
	luaL_checktype(L, 2, LUA_TTABLE); /* devlist */

	luadev = (luadevice_t *)lua_newuserdatauv(L, sizeof(luadevice_t), LUADEVICE_DEVLISTUV);
	luadev->count = (unsigned int)lua_rawlen(L, 2);
	luadev->L = L;
	luadev->ud = LUA_NOREF;

	if ((ret = alloc_chrdev_region(&luadev->major, LUADEVICE_FIRSTMINOR, luadev->count, name) != 0))
		luaL_error(L, "failed to allocate device (%d)", ret);

	luaL_setmetatable(L, LUADEVICE_MT);
	lua_pushvalue(L, 2);  /* push devlist */
	lua_setiuservalue(L, -2, 1);

	cdev_init(&luadev->cdev, &luadevice_fops);
	if ((ret = cdev_add(&luadev->cdev, luadev->major, luadev->count)) != 0)
		luaL_error(L, "failed to add cdev (%d)", ret);
	lua_pushvalue(L, -1);  /* push userdata */
	luadev->ud = luaL_ref(L, LUA_REGISTRYINDEX); /* cdev added (for __gc) */

	luadevice_createminors(luadev, name, 2);
	return 1;
}

static int luadevice_destroy(lua_State *L)
{
	luadevice_t *luadev;

	luadev = (luadevice_t *)luaL_checkudata(L, 1, LUADEVICE_MT);
	if (luadev->ud != LUA_NOREF) /* was cdev added? */
		cdev_del(&luadev->cdev);
	luadevice_destroyminors(luadev); /* it's safe to destroy uncreated minors */
	unregister_chrdev_region(luadev->major, luadev->count);
	luaL_unref(L, LUA_REGISTRYINDEX, luadev->ud);
	return 0;
}

static const luaL_Reg luadevice_lib[] = {
	{"create", luadevice_create},
	{"destroy", luadevice_destroy},
	{NULL, NULL}
};

static const luaL_Reg luadevice_mt[] = {
	{"__gc", luadevice_destroy},
	{"__close", luadevice_destroy},
	{"destroy", luadevice_destroy},
	{NULL, NULL}
};

int luaopen_device(lua_State *L)
{
	luaL_newlib(L, luadevice_lib);
	luaL_newmetatable(L, LUADEVICE_MT);
	luaL_setfuncs(L, luadevice_mt, 0);
	lua_pushvalue(L, -1);  /* push lib */
	lua_setfield(L, -2, "__index");  /* mt.__index = lib */
	lua_pop(L, 1);  /* pop mt */
	return 1;
}
EXPORT_SYMBOL(luaopen_device);

static char *luadevice_checkmode(struct device *dev, umode_t *mode)
{
	luadevice_t *luadev;

	if (!mode)
		goto out;

	luadev = (luadevice_t *)dev_get_drvdata(dev);
	if (luadevice_getminor(luadev->L, luadev->ud, MINOR(dev->devt)) == 0 &&
	    lua_getfield(luadev->L, -1, "mode") == LUA_TNUMBER)
		*mode = (umode_t)lua_tointeger(luadev->L, -1);
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
	luadevice_class->devnode = luadevice_checkmode;
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

