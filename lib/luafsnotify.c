/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Filesystem notification.
* Places marks on filesystem objects and hands the events they report to a Lua
* callback. Event masks are the `linux.fs` bits.
*
* Delivery is synchronous: the callback runs inside the syscall of the process
* performing the access, holding the runtime lock, so every watched access on
* the machine is serialized behind it.
*
* @module fsnotify
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/dcache.h>
#include <linux/fsnotify_backend.h>
#include <linux/list.h>
#include <linux/namei.h>
#include <linux/path.h>

#include <lunatik.h>

/***
* Watches filesystem objects.
* A userdata returned by `fsnotify.watch()`, owning an `fsnotify` group and
* every mark placed through it.
* @type fsnotify_watch
*/
typedef struct luafsnotify_s {
	struct fsnotify_group *group;
	lunatik_object_t *runtime;
	struct list_head marks;
} luafsnotify_t;

typedef struct luafsnotify_mark_s {
	struct fsnotify_mark mark;
	struct list_head entry;
} luafsnotify_mark_t;

static const lunatik_class_t luafsnotify_class;

LUNATIK_PRIVATECHECKER(luafsnotify_check, luafsnotify_t *, &luafsnotify_class);

static int luafsnotify_callback(lua_State *L, luafsnotify_t *watch, __u32 mask)
{
	if (lunatik_getregistry(L, watch) != LUA_TFUNCTION)
		return 0; /* callback removed by stop() */

	lua_pushinteger(L, (lua_Integer)mask);
	if (lua_pcall(L, 1, 0, 0) != LUA_OK) /* callback(mask) */
		pr_err_ratelimited("%s\n", lua_tostring(L, -1));
	return 0;
}

static int luafsnotify_event(struct fsnotify_mark *mark, u32 mask, struct inode *inode,
	struct inode *dir, const struct qstr *name, u32 cookie)
{
	luafsnotify_t *watch = (luafsnotify_t *)mark->group->private;
	int ret;

	/* whoever holds the runtime lock lands back here when it touches a marked
	 * path; the nesting has no floor, so skip rather than run */
	if (lunatik_isowner(watch->runtime))
		return 0;

	lunatik_run(watch->runtime, luafsnotify_callback, ret, watch, mask);
	(void)ret;
	return 0; /* fsnotify only reads this for permission events */
}

static void luafsnotify_freemark(struct fsnotify_mark *mark)
{
	lunatik_free(container_of(mark, luafsnotify_mark_t, mark));
}

static void luafsnotify_freegroup(struct fsnotify_group *group)
{
	luafsnotify_t *watch = (luafsnotify_t *)group->private;

	lunatik_putobject(watch->runtime);
	lunatik_free(watch);
}

static const struct fsnotify_ops luafsnotify_ops = {
	.handle_inode_event = luafsnotify_event,
	.free_mark = luafsnotify_freemark,
	.free_group_priv = luafsnotify_freegroup,
};

/* the group outlives this call: a mark can still be running an event under
 * fsnotify's SRCU, and waiting for it here would deadlock against the runtime
 * lock that event blocks on. free_group_priv frees the watch instead. */
static void luafsnotify_detach(luafsnotify_t *watch)
{
	struct fsnotify_group *group = watch->group;
	luafsnotify_mark_t *mark, *next;

	if (group == NULL)
		return;

	watch->group = NULL;
	list_for_each_entry_safe(mark, next, &watch->marks, entry) {
		list_del(&mark->entry);
		fsnotify_destroy_mark(&mark->mark, group);
		fsnotify_put_mark(&mark->mark); /* the reference fsnotify_init_mark left us */
	}
	fsnotify_put_group(group);
}

static void luafsnotify_release(void *private)
{
	luafsnotify_detach((luafsnotify_t *)private);
}

/***
* Places a mark on a filesystem object.
* Resolves `path` and marks its inode for the events in `mask`. A mark on a
* directory reports events on the files inside it only when `mask` carries
* `linux.fs.EVENT_ON_CHILD`.
* @function mark
* @tparam string path path of the object to mark
* @tparam integer mask event mask, a combination of `linux.fs` bits
* @treturn nil
* @raise if `path` does not resolve, if the mark cannot be added, if the watch
*   has been stopped, or if `mask` carries a permission event
* @usage watch:mark("/tmp/scratch/file", fs.OPEN | fs.MODIFY)
*/
static int luafsnotify_mark(lua_State *L)
{
	luafsnotify_t *watch = luafsnotify_check(L, 1);
	const char *pathname = luaL_checkstring(L, 2);
	__u32 mask = (__u32)luaL_checkinteger(L, 3);
	luafsnotify_mark_t *mark;
	struct path path;
	int ret;

	/* the verdict such an event asks for is not implemented */
	luaL_argcheck(L, !(mask & ALL_FSNOTIFY_PERM_EVENTS), 3, "permission events not supported");

	mark = (luafsnotify_mark_t *)lunatik_checkzalloc(L, sizeof(luafsnotify_mark_t));

	if ((ret = kern_path(pathname, LOOKUP_FOLLOW, &path)) != 0) {
		lunatik_free(mark);
		lunatik_throw(L, ret);
	}

	fsnotify_init_mark(&mark->mark, watch->group);
	mark->mark.mask = mask;

	ret = fsnotify_add_inode_mark(&mark->mark, d_inode(path.dentry), 0);
	path_put(&path);

	if (ret != 0) {
		fsnotify_put_mark(&mark->mark); /* frees through free_mark */
		lunatik_throw(L, ret);
	}

	list_add(&mark->entry, &watch->marks);
	return 0;
}

/***
* Stops the watch.
* Removes every mark it placed and releases its group, so no further event
* reaches the callback. Calling it again does nothing.
* @function stop
* @treturn nil
* @usage watch:stop()
*/
static int luafsnotify_stop(lua_State *L)
{
	lunatik_object_t *object = lunatik_checkobjectclass(L, 1, &luafsnotify_class);
	luafsnotify_t *watch = (luafsnotify_t *)object->private;

	if (watch == NULL) /* already stopped */
		return 0;

	lunatik_unregisterobject(L, object);
	object->private = NULL; /* the group frees the watch; release must not run on it */
	luafsnotify_detach(watch);
	return 0;
}

static inline struct fsnotify_group *luafsnotify_allocgroup(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(5, 19, 0))
	return fsnotify_alloc_group(&luafsnotify_ops, 0); /* not FSNOTIFY_GROUP_USER: that accounts a userspace fd */
#else
	return fsnotify_alloc_group(&luafsnotify_ops);
#endif
}

static luafsnotify_t *luafsnotify_newwatch(lua_State *L, lunatik_object_t *runtime)
{
	luafsnotify_t *watch = (luafsnotify_t *)lunatik_checkzalloc(L, sizeof(luafsnotify_t));
	struct fsnotify_group *group = luafsnotify_allocgroup();

	if (IS_ERR(group)) {
		lunatik_free(watch);
		lunatik_throw(L, (int)PTR_ERR(group));
	}

	INIT_LIST_HEAD(&watch->marks);
	watch->runtime = runtime;
	watch->group = group;
	lunatik_getobject(runtime);
	group->private = watch; /* the group owns the watch from here on */
	return watch;
}

/***
* Creates a watch.
* Allocates an `fsnotify` group whose events are delivered to `callback`.
* Nothing arrives until `watch:mark` places a mark.
*
* An event whose delivery would need a lock its own task already holds is
* dropped rather than run: this callback touching a path it marks, and equally
* a `thread` body, a `device` file operation or another module's callback in
* the same runtime.
* @function watch
* @tparam function callback invoked as `callback(mask)`, where `mask` is the
*   event mask that fired, testable against `linux.fs` bits. Its return value
*   is ignored.
* @treturn fsnotify_watch
* @raise if the group cannot be allocated, if called from an interrupt-context
*   runtime, or if called from a percpu runtime
* @within fsnotify
* @usage
*   local watch = fsnotify.watch(function (mask) print(mask) end)
*   watch:mark("/tmp/scratch", fs.OPEN)
*/
static int luafsnotify_watch(lua_State *L)
{
	lunatik_checkpercpu(L);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	lunatik_object_t *runtime = lunatik_checkruntime(L, luafsnotify_class.opt);
	lunatik_object_t *object = lunatik_newobject(L, &luafsnotify_class, 0, LUNATIK_OPT_NONE);

	object->private = luafsnotify_newwatch(L, runtime);
	lunatik_registerobject(L, 1, object);
	return 1; /* object */
}

static const luaL_Reg luafsnotify_lib[] = {
	{"watch", luafsnotify_watch},
	{NULL, NULL}
};

static const luaL_Reg luafsnotify_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"mark", luafsnotify_mark},
	{"stop", luafsnotify_stop},
	{NULL, NULL}
};

LUNATIK_OPENER(fsnotify);
static const lunatik_class_t luafsnotify_class = {
	.name = "fsnotify",
	.methods = luafsnotify_mt,
	.release = luafsnotify_release,
	.opener = luaopen_fsnotify,
	.opt = LUNATIK_OPT_SINGLE | LUNATIK_OPT_EXTERNAL,
};

LUNATIK_CLASSES(fsnotify, &luafsnotify_class);
LUNATIK_NEWLIB(fsnotify, luafsnotify_lib, luafsnotify_classes);

static int __init luafsnotify_init(void)
{
	return 0;
}

static void __exit luafsnotify_exit(void)
{
	/* free_mark and free_group_priv run from fsnotify's reaper */
	fsnotify_wait_marks_destroyed();
}

module_init(luafsnotify_init);
module_exit(luafsnotify_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

