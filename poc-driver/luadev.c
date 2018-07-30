#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/printk.h>
#include <linux/string.h>
#include <linux/device.h>
#include <linux/cdev.h>
#include <linux/uaccess.h>
#include <linux/kthread.h>

#include <lua/lua.h>
#include <lua/lualib.h>
#include <lua/lauxlib.h>

#include <rcu/rcu.h>

MODULE_LICENSE("GPL");

#define DEVICE_NAME "luadrv"
#define CLASS_NAME "lua"

#define raise_err(msg) pr_warn("[lua] %s - %s\n", __func__, msg);

static DEFINE_MUTEX(dev_mtx);

static int major;
static struct device *luadev;
static struct class *luaclass;
static struct cdev luacdev;

#define NSTATES 4

struct lua_exec {
    int id;
    lua_State *L;
    char *script;    
    struct task_struct *kthread;
    struct mutex lock; 
};

static struct lua_exec lua_states[NSTATES];

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
    int i;
    
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
    
    for (i = 0; i < NSTATES; i++) {
        lua_states[i].id = i;        
        lua_states[i].L = luaL_newstate();
        
        if (lua_states[i].L == NULL ) {
	    	raise_err("no memory");
	    	return -ENOMEM;
        }
        
        luaL_openlibs(lua_states[i].L);
        luaL_requiref(lua_states[i].L, "rcu", luaopen_rcu, 1);
        mutex_init(&lua_states[i].lock);
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
    
    mutex_lock(&dev_mtx);
    if (copy_to_user(buf, msg, len) < 0) {
        raise_err("copy to user failed");
        mutex_unlock(&dev_mtx);
        return -ECANCELED;
    }
    mutex_unlock(&dev_mtx);
    return strlen(msg) < len ? strlen(msg) : len;
}

static int flush(lua_State *L)
{
    lua_close(L);
    L = luaL_newstate();
    if (L == NULL) {
        raise_err("flushL failed, giving up");
        return 1;
    }
    
    luaL_openlibs(L);
    luaL_requiref(L, "rcu", luaopen_rcu, 1);    
    return 0;
}

static int thread_fn(void *arg)
{
    struct lua_exec *lua = arg;    
    set_current_state(TASK_INTERRUPTIBLE);
    
    printk("running thread %d", lua->id);
    if (luaL_dostring(lua->L, lua->script)) {
        printk("script error, flushing the state");
        raise_err(lua_tostring(lua->L, -1));
        flush(lua->L);
        mutex_unlock(&lua->lock);
        return -ECANCELED;
    }    
    kfree(lua->script);
    mutex_unlock(&lua->lock);
        
    printk("thread %d finished", lua->id);
    return 0;
}

static ssize_t dev_write(struct file *f, const char *buf, size_t len,
        loff_t* off)
{
    int i;
    char *script = NULL;

    mutex_lock(&dev_mtx);
    script = kmalloc(len, GFP_KERNEL);
    if (script == NULL) {
        raise_err("no memory");
        return -ENOMEM;
    }
    if (copy_from_user(script, buf, len) < 0) {
        raise_err("copy from user failed");
        mutex_unlock(&dev_mtx);
        return -ECANCELED;
    }
    script[len-1] = '\0';
    
    for (i = 0; i < NSTATES; i++) {
        if (mutex_trylock(&lua_states[i].lock)) {
            lua_states[i].script = script;
            lua_states[i].kthread = kthread_run(thread_fn, &lua_states[i], "load2state");
            mutex_unlock(&dev_mtx);
            return len;
        }
    }
    
    raise_err("all lua states are busy");
    mutex_unlock(&dev_mtx);
    return -EBUSY;
}

static int dev_release(struct inode *i, struct file *f)
{
    return 0;
}

module_init(luadrv_init);
module_exit(luadrv_exit);
