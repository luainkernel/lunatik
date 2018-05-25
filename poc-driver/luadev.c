#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/printk.h>
#include <linux/string.h>
#include <linux/device.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>

#include <lua/lua.h>
#include <lua/lualib.h>
#include <lua/lauxlib.h>

#include <rcu/rcu.h>

MODULE_LICENSE("GPL");

#define DEVICE_NAME "luadrv"
#define CLASS_NAME "lua"

#define raise_err(msg) pr_warn("[lua] %s - %s\n", __func__, msg);

static DEFINE_MUTEX(mtx);

static int major;
static lua_State *L;
bool hasreturn = 0; /* does the lua state have anything for us? */
static struct device *luadev;
static struct class *luaclass;
static struct cdev luacdev;

static int dev_open(struct inode*, struct file*);
static int dev_release(struct inode*, struct file*);
static ssize_t dev_read(struct file*, char*, size_t, loff_t*);
static ssize_t dev_write(struct file*, const char*, size_t, loff_t*);

static struct file_operations fops =
{
    .open = dev_open,
    .read = dev_read,
    .write = dev_write,
    .release = dev_release
};

static int __init luadrv_init(void)
{
    L = luaL_newstate();
    if (L == NULL) {
		raise_err("no memory");
		return -ENOMEM;
    }
    
    luaL_openlibs(L);
    luaL_requiref(L, "rcu", luaopen_rcu, 1);

    major = register_chrdev(0, DEVICE_NAME, &fops);
    if (major < 0) {
        raise_err("major number failed");
        return -ECANCELED;
    }
    luaclass = class_create(THIS_MODULE, CLASS_NAME);
    if (IS_ERR(luaclass)) {
        unregister_chrdev(major, DEVICE_NAME);
        raise_err("class failed");
        return PTR_ERR(luaclass);
    }
    luadev = device_create(luaclass, NULL, MKDEV(major, 1),
            NULL, "%s", DEVICE_NAME);
    if (IS_ERR(luadev)) {
        class_destroy(luaclass);
        cdev_del(&luacdev);
        unregister_chrdev(major, DEVICE_NAME);
        raise_err("device failed");
        return PTR_ERR(luaclass);
    }
    pr_err("major - %d / minor - 1\n", major);
    return 0;
}
static void __exit luadrv_exit(void) 
{
    return;
}

static int dev_open(struct inode *i, struct file *f)
{
    return 0;
}

static ssize_t dev_read(struct file *f, char *buf, size_t len, loff_t *off)
{
    const char *msg = "Nothing yet.\n";

    mutex_lock(&mtx);
    if (hasreturn) {
        msg = lua_tostring(L, -1);
        hasreturn = false;
    }
    if (copy_to_user(buf, msg, len) < 0) {
        raise_err("copy to user failed");
        mutex_unlock(&mtx);
        return -ECANCELED;
    }
    mutex_unlock(&mtx);
    return strlen(msg) < len ? strlen(msg) : len;
}

static int flushL(void)
{
    lua_close(L);
    L = luaL_newstate();
    if (L == NULL) {
        raise_err("flushL failed, giving up");
        mutex_unlock(&mtx);
        return 1;
    }
    
    luaL_openlibs(L);
    luaL_requiref(L, "rcu", luaopen_rcu, 1);    
    return 0;
}

static ssize_t dev_write(struct file *f, const char *buf, size_t len,
        loff_t* off)
{
    char *script = NULL;
    int idx = lua_gettop(L);

    mutex_lock(&mtx);
    script = kmalloc(len, GFP_KERNEL);
    if (script == NULL) {
        raise_err("no memory");
        return -ENOMEM;
    }
    if (copy_from_user(script, buf, len) < 0) {
        raise_err("copy from user failed");
        mutex_unlock(&mtx);
        return -ECANCELED;
    }
    script[len-1] = '\0';
    if (luaL_dostring(L, script)) {
        printk("script error, flushing the state");
        raise_err(lua_tostring(L, -1));
        if (flushL()) {
            return -ECANCELED;
        }
        mutex_unlock(&mtx);
        return -ECANCELED;
    }
    kfree(script);
    hasreturn = lua_gettop(L) > idx ? true : false;
    mutex_unlock(&mtx);
    return len;
}

static int dev_release(struct inode *i, struct file *f)
{
    mutex_lock(&mtx);
//    if (flushL()) {
//        return -ECANCELED;
//    }
    hasreturn = false;
    mutex_unlock(&mtx);
    return 0;
}

module_init(luadrv_init);
module_exit(luadrv_exit);
