/*
* Copyright (c) 2023-2024 ring-0 Ltda.
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
#include <linux/version.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include <lunatik.h>

static struct class *luadevice_devclass;

typedef struct luadevice_s {
	struct list_head entry;
	lunatik_object_t *runtime;
	struct cdev *cdev;
	dev_t devt;
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
	list_del(&luadev->entry);
	luadevice_unlock();
}

static inline luadevice_t *luadevice_find(dev_t devt)
{
	luadevice_t *luadev = NULL;
	luadevice_lock();
	luadevice_foreach(luadev) {
		if (luadev->devt == devt)
			break;
	}
	luadevice_unlock();
	return luadev;
}

static int luadevice_new(lua_State *L);

static int luadevice_fop(lua_State *L, luadevice_t *luadev, const char *fop, int nargs, int nresults)
{
	int base = lua_gettop(L) - nargs;
	int ret = -ENXIO;

	if (lunatik_getregistry(L, luadev) != LUA_TTABLE) {
		pr_err("%s: couldn't find driver\n", fop);
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

static int luadevice_doopen(lua_State *L, luadevice_t *luadev)
{
	return luadevice_fop(L, luadev, "open", 0, 0);
}

static ssize_t luadevice_doread(lua_State *L, luadevice_t *luadev, char *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	size_t llen;
	const char *lbuf;

	lua_pushinteger(L, len);
	lua_pushinteger(L, *off);
	if ((ret = luadevice_fop(L, luadev, "read", 2, 2)) != 0)
		return ret;

	lbuf = lua_tolstring(L, -2, &llen);
	llen = min(len, llen);
	if (copy_to_user(buf, lbuf, llen) != 0)
		return -EFAULT;

	*off = (loff_t)luaL_optinteger(L, -1, *off + llen);
	return (ssize_t)llen;
}

static ssize_t luadevice_dowrite(lua_State *L, luadevice_t *luadev, const char *buf, size_t len, loff_t *off)
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
	if ((ret = luadevice_fop(L, luadev, "write", 2, 2)) != 0)
		return ret;

	llen = (size_t)luaL_optinteger(L, -2, len);
	llen = min(len, llen);
	*off = (loff_t)luaL_optinteger(L, -1, *off + llen);
	return (ssize_t)llen;
}

static int luadevice_dorelease(lua_State *L, luadevice_t *luadev)
{
	return luadevice_fop(L, luadev, "release", 0, 0);
}

#define luadevice_fromfile(f)	((luadevice_t *)(f)->private_data)
#define luadevice_run(handler, ret, f, ...)					\
		lunatik_run(luadevice_fromfile(f)->runtime, (handler),	\
			(ret), luadevice_fromfile(f), ## __VA_ARGS__)

static int luadevice_fop_open(struct inode *inode, struct file *f)
{
	luadevice_t *luadev;
	int ret;

	if ((luadev = luadevice_find(inode->i_rdev)) == NULL)
		return -ENXIO;

	lunatik_getobject(luadev->runtime);
	f->private_data = luadev;
	luadevice_run(luadevice_doopen, ret, f);
	return ret;
}

static ssize_t luadevice_fop_read(struct file *f, char *buf, size_t len, loff_t *off)
{
	ssize_t ret;
	luadevice_run(luadevice_doread, ret, f, buf, len, off);
	return ret;
}

static ssize_t luadevice_fop_write(struct file *f, const char *buf, size_t len, loff_t* off)
{
	ssize_t ret;
	luadevice_run(luadevice_dowrite, ret, f, buf, len, off);
	return ret;
}

static int luadevice_fop_release(struct inode *inode, struct file *f)
{
	int ret;

	luadevice_run(luadevice_dorelease, ret, f);
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
	if (luadev->cdev != NULL) {
		cdev_del(luadev->cdev);
		luadev->cdev = NULL;
	}

	if (luadev->devt != 0) {
		luadevice_listdel(luadev);
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
	lunatik_putobject(luadev->runtime);
}

static int luadevice_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobject(L, 1);
	luadevice_t *luadev = (luadevice_t *)object->private;

	lunatik_lock(object);
	luadevice_delete(luadev);
	lunatik_unlock(object);

	if (lunatik_toruntime(L) == luadev->runtime)
		lunatik_unregisterobject(L, object);
	return 0;
}

static const luaL_Reg luadevice_lib[] = {
	{"new", luadevice_new},
	{NULL, NULL}
};

static const luaL_Reg luadevice_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"stop", luadevice_stop},
	{NULL, NULL}
};

static const lunatik_class_t luadevice_class = {
	.name = "device",
	.methods = luadevice_mt,
	.release = luadevice_release,
	.sleep = true,
};

static int luadevice_new(lua_State *L)
{
	lunatik_object_t *object;
	luadevice_t *luadev;
	struct device *device;
	const char *name;
	int tname;
	int ret;

	luaL_checktype(L, 1, LUA_TTABLE); /* driver */
	if ((tname = lua_getfield(L, -1, "name")) != LUA_TSTRING) /* driver.name */
		luaL_error(L, "bad field 'name' (string expected, got %s)", lua_typename(L, tname));
	name = lua_tostring(L, -1);

	object = lunatik_newobject(L, &luadevice_class, sizeof(luadevice_t));
	luadev = (luadevice_t *)object->private;

	memset(luadev, 0, sizeof(luadevice_t));

	luadev->runtime = lunatik_toruntime(L);
	lunatik_getobject(luadev->runtime);

	if ((ret = alloc_chrdev_region(&luadev->devt, 0, 1, name) != 0))
		luaL_error(L, "failed to allocate char device region (%d)", ret);

	if ((luadev->cdev = cdev_alloc()) == NULL)
		luaL_error(L, "failed to allocate cdev");
	luadev->cdev->ops = &luadevice_fops;
	if ((ret = cdev_add(luadev->cdev, luadev->devt, 1)) != 0)
		luaL_error(L, "failed to add cdev (%d)", ret);

	luadevice_listadd(luadev);
	lunatik_registerobject(L, 1, object); /* driver */

	device = device_create(luadevice_devclass, NULL, luadev->devt, luadev, name); /* calls devnode */
	if (IS_ERR(device)) {
		lunatik_unregisterobject(L, object);
		luaL_error(L, "failed to create a new device (%d)", PTR_ERR(device));
	}
	lua_remove(L, -2); /* remove name */

	return 1; /* object */
}

LUNATIK_NEWLIB(device, luadevice_lib, &luadevice_class, NULL);

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 2, 0)
static char *luadevice_devnode(const struct device *dev, umode_t *mode)
#else
static char *luadevice_devnode(struct device *dev, umode_t *mode)
#endif
{
	lua_State *L;
	luadevice_t *luadev;
	int base;

	if (!mode)
		goto out;

	luadev = (luadevice_t *)dev_get_drvdata(dev);
	L = lunatik_getstate(luadev->runtime);
	if (!L)
		goto out;

	base = lua_gettop(L);
	if (lunatik_getregistry(L, luadev) == LUA_TTABLE && lua_getfield(L, -1, "mode") == LUA_TNUMBER)
		*mode = (umode_t)lua_tointeger(L, -1);
	lua_settop(L, base);
out:
	return NULL;
}

static int __init luadevice_init(void)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0)
	luadevice_devclass = class_create("luadevice");
#else
	luadevice_devclass = class_create(THIS_MODULE, "luadevice");
#endif
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
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ring-0.io>");

