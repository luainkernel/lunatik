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

static struct class *luadevice_devclass;

typedef struct luadevice_s {
	struct list_head entry;
	struct kref kref;
	lunatik_runtime_t *runtime;
	struct cdev *cdev;
	dev_t devt;
	int ud;
} luadevice_t;

static DEFINE_MUTEX(luadevice_mutex);
static LIST_HEAD(luadevice_list);

#define luadevice_lock()		mutex_lock(&luadevice_mutex)
#define luadevice_unlock()		mutex_unlock(&luadevice_mutex)
#define luadevice_foreach(luadev)	list_for_each_entry((luadev), &luadevice_list, entry)

static void luadevice_free(struct kref *kref)
{
	luadevice_t *luadev = container_of(kref, luadevice_t, kref);
	kfree(luadev);
}

#define luadevice_refinit(luadev)	kref_init(&(luadev)->kref)
#define luadevice_get(luadev)		kref_get(&(luadev)->kref)
#define luadevice_put(luadev)		kref_put(&(luadev)->kref, luadevice_free)

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

static inline luadevice_t *luadevice_alloc(lua_State *L)
{
	luadevice_t *luadev;
	if ((luadev = (luadevice_t *)kzalloc(sizeof(luadevice_t), GFP_KERNEL)) == NULL)
		return NULL;
	luadev->runtime = lunatik_toruntime(L);
	luadevice_refinit(luadev);
	luadevice_listadd(luadev);
	return luadev;
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

#define LUADEVICE_MT	"device"

#define luadevice_userdata(L, ud)	(lua_rawgeti((L), LUA_REGISTRYINDEX, (ud)) != LUA_TUSERDATA)
#define luadevice_driver(L, ix)		(lua_getiuservalue((L), (ix), 1) != LUA_TTABLE)

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
	return luadevice_fop(L, ud, "open", 0, 0);
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
	return luadevice_fop(L, ud, "release", 0, 0);
}

#define luadevice_fromfile(f)	((luadevice_t *)(f)->private_data)
#define luadevice_run(handler, ret, f, ...)					\
		lunatik_run(luadevice_fromfile(f)->runtime, (handler),		\
			(ret), luadevice_fromfile(f)->ud, ## __VA_ARGS__)

static int luadevice_open(struct inode *inode, struct file *f)
{
	luadevice_t *luadev;
	int ret;

	if ((luadev = luadevice_find(inode->i_rdev)) == NULL)
		return -ENXIO;

	luadevice_get(luadev);
	lunatik_get(luadev->runtime);
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

static int luadevice_release(struct inode *inode, struct file *f)
{
	luadevice_t *luadev;
	int ret;

	luadevice_run(luadevice_dorelease, ret, f);
	luadev = luadevice_fromfile(f);
	lunatik_put(luadev->runtime);
	luadevice_put(luadev);
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
	luadevice_t *luadev;
	luadevice_t **pluadev;
	struct device *device;
	const char *name;
	int tname;
	int ret;

	luaL_checktype(L, 1, LUA_TTABLE); /* driver */
	if ((tname = lua_getfield(L, -1, "name")) != LUA_TSTRING) /* driver.name */
		luaL_error(L, "bad field 'name' (string expected, got %s)", lua_typename(L, tname));
	name = lua_tostring(L, -1);

	pluadev = (luadevice_t **)lua_newuserdatauv(L, sizeof(luadevice_t), 1);

	if ((luadev = luadevice_alloc(L)) == NULL)
		luaL_error(L, "failed to allocate device context");
	*pluadev = luadev;

	luadev->ud = LUA_NOREF;

	luaL_setmetatable(L, LUADEVICE_MT); /* __gc() is set for cleanup */
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
	device = device_create(luadevice_devclass, NULL, luadev->devt, luadev, name); /* calls devnode */
	if (IS_ERR(device))
		luaL_error(L, "failed to create a new device (%d)", PTR_ERR(device));
	lua_pop(L, 1); /* pop driver */
	lua_remove(L, -2); /* remove driver.name */

	return 1; /* userdata */
}

static int luadevice_delete(lua_State *L)
{
	luadevice_t *luadev;
	luadevice_t **pluadev;

	pluadev = (luadevice_t **)luaL_checkudata(L, 1, LUADEVICE_MT);
	luadev = *pluadev;

	if (luadev->cdev != NULL)
		cdev_del(luadev->cdev);

	if (luadev->devt != 0) {
		device_destroy(luadevice_devclass, luadev->devt);
		unregister_chrdev_region(luadev->devt, 1);
	}

	luaL_unref(L, LUA_REGISTRYINDEX, luadev->ud);
	luadevice_listdel(luadev);
	luadevice_put(luadev);
	return 0;
}

static int luadevice_set(lua_State *L)
{
	luaL_checkudata(L, 1, LUADEVICE_MT);
	if (luadevice_driver(L, 1) != 0)
		luaL_error(L, "couln't find driver");

	lua_replace(L, 1); /* driver -> userdata */
	lua_settable(L, 1); /* driver[key] = value */
	return 0;
}

static const luaL_Reg luadevice_lib[] = {
	{"new", luadevice_new},
	{"delete", luadevice_delete},
	{"set", luadevice_set},
	{NULL, NULL}
};

static const luaL_Reg luadevice_mt[] = {
	{"__gc", luadevice_delete},
	{"__close", luadevice_delete},
	{"__newindex", luadevice_set},
	{"delete", luadevice_delete},
	{"set", luadevice_set},
	{NULL, NULL}
};

static const lunatik_class_t luadevice_class = {
	.name = LUADEVICE_MT,
	.methods = luadevice_mt,
	.sleep = true,
};

LUNATIK_NEWLIB(device, luadevice_lib, &luadevice_class, NULL);

static char *luadevice_devnode(struct device *dev, umode_t *mode)
{
	lua_State *L;
	luadevice_t *luadev;
	int base;

	if (!mode)
		goto out;

	luadev = (luadevice_t *)dev_get_drvdata(dev);
	L = luadev->runtime->L;

	base = lua_gettop(L);
	if (luadevice_getdriver(L, luadev->ud) == 0 && lua_getfield(L, -1, "mode") == LUA_TNUMBER)
		*mode = (umode_t)lua_tointeger(L, -1);
	lua_settop(L, base);
out:
	return NULL;
}

static int __init luadevice_init(void)
{
	luadevice_devclass = class_create(THIS_MODULE, "luadevice");
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

