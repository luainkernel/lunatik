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
#include <linux/limits.h>
#include <linux/list.h>
#include <linux/namei.h>
#include <linux/path.h>
#include <linux/pid.h>

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
	lunatik_object_t *event;
	struct list_head marks;
} luafsnotify_t;

typedef struct luafsnotify_mark_s {
	struct fsnotify_mark mark;
	struct list_head entry;
} luafsnotify_mark_t;

/* the dispatcher's frame, borrowed by the event object for the length of one call */
typedef struct luafsnotify_event_s {
	const void *data;
	const struct qstr *name;
	struct inode *dir;
	int data_type;
	pid_t pid;
	__u32 mask;
} luafsnotify_event_t;

static const lunatik_class_t luafsnotify_class;
static const lunatik_class_t luafsnotify_event_class;

LUNATIK_PRIVATECHECKER(luafsnotify_check, luafsnotify_t *, &luafsnotify_class);

LUNATIK_PRIVATECHECKER(luafsnotify_checkevent, luafsnotify_event_t *, &luafsnotify_event_class);

static inline lunatik_object_t *luafsnotify_pushevent(lua_State *L, luafsnotify_t *watch,
	luafsnotify_event_t *event)
{
	lunatik_object_t *object = watch->event;

	if (lunatik_getregistry(L, object) != LUA_TUSERDATA) {
		pr_err("couldn't find event\n");
		return NULL;
	}

	object->private = event;
	return object;
}

static int luafsnotify_callback(lua_State *L, luafsnotify_t *watch, luafsnotify_event_t *event)
{
	lunatik_object_t *object;

	if (lunatik_getregistry(L, watch) != LUA_TFUNCTION)
		return 0; /* callback removed by stop() */

	lua_pushinteger(L, (lua_Integer)event->mask);
	if ((object = luafsnotify_pushevent(L, watch, event)) == NULL)
		return 0;

	if (lua_pcall(L, 2, 0, 0) != LUA_OK) /* callback(mask, event) */
		pr_err_ratelimited("%s\n", lua_tostring(L, -1));

	object->private = NULL; /* the frame it points at goes next: a kept event raises instead */
	return 0;
}

static int luafsnotify_handle(struct fsnotify_group *group, u32 mask, const void *data, int data_type,
	struct inode *dir, const struct qstr *name, u32 cookie, struct fsnotify_iter_info *iter_info)
{
	luafsnotify_t *watch = (luafsnotify_t *)group->private;
	luafsnotify_event_t event = {
		.data = data,
		.name = name,
		.dir = dir,
		.data_type = data_type,
		.pid = task_pid_nr(current), /* delivery is synchronous: this is the accessing task */
		.mask = mask,
	};
	int ret;

	/* whoever holds the runtime lock lands back here when it touches a marked
	 * path; the nesting has no floor, so skip rather than run */
	if (lunatik_isowner(watch->runtime))
		return 0;

	lunatik_run(watch->runtime, luafsnotify_callback, ret, watch, &event);
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
	/* not handle_inode_event: only this variant is handed the event's data and its
	 * type, which is where event:path() finds its struct path */
	.handle_event = luafsnotify_handle,
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
	if (watch->event != NULL) /* NULL when attaching one raised */
		lunatik_detach(watch->runtime, watch, event); /* fsnotify_put_group below frees the watch */
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

/***
* The event a watch hands to its callback.
* A userdata reused for every event of the watch that made it, holding what the
* kernel passed the dispatcher. It is cleared when the callback returns, so a
* script that keeps it and reads it afterwards gets an error rather than a
* pointer into a stack frame that is gone.
*
* What an accessor can answer depends on what the kernel attached to the event:
* an event on an open file carries a `struct path` and answers everything, while
* a directory entry event carries only the entry's dentry or inode and has no
* path. Each accessor returns `nil` for a field the event does not carry.
* @type fsnotify_event
*/

/***
* Returns the directory entry name the event is about.
* Carried by the directory entry events (`CREATE`, `DELETE`, `MOVED_FROM`,
* `MOVED_TO`) and by an event a parent directory marked with
* `linux.fs.EVENT_ON_CHILD` is interested in; an event only the object's own
* mark reports carries none.
* @function name
* @treturn string entry name, or `nil` when the event carries none
* @raise if the event is used after its callback returned
*/
static int luafsnotify_name(lua_State *L)
{
	luafsnotify_event_t *event = luafsnotify_checkevent(L, 1);
	const struct qstr *name = event->name;

	if (name == NULL)
		lua_pushnil(L);
	else
		lua_pushlstring(L, (const char *)name->name, name->len);
	return 1;
}

/***
* Returns the inode number of the object the event is about.
* Absent only when the kernel attached neither an inode, a dentry nor a path to
* the event, and for a directory entry whose inode the filesystem instantiates
* after reporting the entry.
* @function ino
* @treturn integer inode number, or `nil` when the event carries no inode
* @raise if the event is used after its callback returned
*/
static int luafsnotify_ino(lua_State *L)
{
	luafsnotify_event_t *event = luafsnotify_checkevent(L, 1);
	struct inode *inode = fsnotify_data_inode(event->data, event->data_type);

	lunatik_pushoptinteger(L, inode, inode->i_ino);
	return 1;
}

/***
* Returns the inode number of the directory the entry the event names lives in.
* Carried by the directory entry events, and by an event on an object whose
* parent directory watches its children, whether or not `name` is.
* @function dir
* @treturn integer inode number, or `nil` when the event names no directory
* @raise if the event is used after its callback returned
*/
static int luafsnotify_dir(lua_State *L)
{
	luafsnotify_event_t *event = luafsnotify_checkevent(L, 1);

	lunatik_pushoptinteger(L, event->dir, event->dir->i_ino);
	return 1;
}

/***
* Tells whether the event is about a directory.
* Reads `linux.fs.ISDIR` off the mask, so it answers for every event.
* @function isdir
* @treturn boolean
* @raise if the event is used after its callback returned
*/
static int luafsnotify_isdir(lua_State *L)
{
	luafsnotify_event_t *event = luafsnotify_checkevent(L, 1);

	lua_pushboolean(L, (event->mask & FS_ISDIR) != 0);
	return 1;
}

/***
* Returns the pid of the task performing the access.
* Delivery is synchronous, in the syscall of the process being watched, so this
* is that process and not a bookkeeping artefact. It is a thread id, the same
* number `task:pid()` reports.
* @function pid
* @treturn integer pid
* @raise if the event is used after its callback returned
*/
static int luafsnotify_pid(lua_State *L)
{
	luafsnotify_event_t *event = luafsnotify_checkevent(L, 1);

	lua_pushinteger(L, (lua_Integer)event->pid);
	return 1;
}

/***
* Returns the full path of the object the event is about.
* Only an event the kernel raised from an open file carries a `struct path`;
* a directory entry event does not, and answers `nil`. This is the expensive
* accessor: it resolves the path into a `PATH_MAX` buffer on every call, so a
* callback that matches on `name` never pays for it.
*
* The path is the one the accessing task sees: `d_path` renders it against that
* task's own root, so a chrooted or containerised accessor gets its own view of
* it, and a file already unlinked carries a trailing `" (deleted)"`.
* @function path
* @treturn string path, or `nil` when the event carries none
* @raise if the path cannot be resolved, or if the event is used after its
*   callback returned
*/
static int luafsnotify_path(lua_State *L)
{
	luafsnotify_event_t *event = luafsnotify_checkevent(L, 1);
	const struct path *path = fsnotify_data_path(event->data, event->data_type);
	luaL_Buffer B;
	char *buffer, *resolved;
	size_t len;

	if (path == NULL) {
		lua_pushnil(L);
		return 1;
	}

	buffer = luaL_buffinitsize(L, &B, PATH_MAX); /* a Lua buffer: a raise below frees it */
	resolved = d_path(path, buffer, PATH_MAX);
	if (IS_ERR(resolved))
		lunatik_throw(L, (int)PTR_ERR(resolved));

	len = strlen(resolved);
	memmove(buffer, resolved, len); /* d_path fills from the end of the buffer */
	luaL_pushresultsize(&B, len);
	return 1;
}

static inline lunatik_object_t *luafsnotify_newevent(lua_State *L)
{
	return lunatik_newobject(L, &luafsnotify_event_class, 0, LUNATIK_OPT_NONE);
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
* Nothing arrives until `watch:mark` places a mark. An event reaches the
* callback once per watch, however many of its marks match it: when a file and
* its parent directory, marked with `linux.fs.EVENT_ON_CHILD`, are both marked
* by the same watch, an event on the file arrives once, tagged
* `EVENT_ON_CHILD` and carrying the entry's `name` and `dir`.
*
* An event whose delivery would need a lock its own task already holds is
* dropped rather than run: this callback touching a path it marks, and equally
* a `thread` body, a `device` file operation or another module's callback in
* the same runtime.
* @function watch
* @tparam function callback invoked as `callback(mask, event)`, where `mask` is
*   the event mask that fired, testable against `linux.fs` bits, and `event` is
*   an `fsnotify_event` valid only for the length of the call. Its return value
*   is ignored.
* @treturn fsnotify_watch
* @raise if the group cannot be allocated, if called from an interrupt-context
*   runtime, or if called from a percpu runtime
* @within fsnotify
* @usage
*   local watch = fsnotify.watch(function (mask, event) print(mask, event:name()) end)
*   watch:mark("/tmp/scratch", fs.OPEN)
*/
static int luafsnotify_watch(lua_State *L)
{
	lunatik_checkpercpu(L);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	lunatik_object_t *runtime = lunatik_checkruntime(L, luafsnotify_class.opt);
	lunatik_object_t *object = lunatik_newobject(L, &luafsnotify_class, 0, LUNATIK_OPT_NONE);
	luafsnotify_t *watch = luafsnotify_newwatch(L, runtime);

	object->private = watch;
	lunatik_attach(L, watch, event, luafsnotify_newevent);
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

static const luaL_Reg luafsnotify_event_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"dir", luafsnotify_dir},
	{"ino", luafsnotify_ino},
	{"isdir", luafsnotify_isdir},
	{"name", luafsnotify_name},
	{"path", luafsnotify_path},
	{"pid", luafsnotify_pid},
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

static const lunatik_class_t luafsnotify_event_class = {
	.name = "fsnotify.event",
	.methods = luafsnotify_event_mt,
	.opt = LUNATIK_OPT_SINGLE | LUNATIK_OPT_EXTERNAL,
};

LUNATIK_CLASSES(fsnotify, &luafsnotify_class, &luafsnotify_event_class);
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

