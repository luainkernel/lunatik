/*
* SPDX-FileCopyrightText: (c) 2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Filesystem notification.
* Places marks on filesystem objects and hands the events they report to a Lua
* callback. Event masks are the `linux.fs` bits.
*
* A mark goes on one inode, on a mount, or on a whole filesystem. The last two
* reach every file they cover, so a mark on the mount or the superblock of `/`
* sends every access on the machine through the callback; mark a scratch
* subtree.
*
* Delivery is synchronous: the callback runs inside the syscall of the process
* performing the access, holding the runtime lock, so every watched access on
* the machine is serialized behind it. That task may also hold the lock of the
* directory the event is about, so `watch:mark`, `watch:find` and `mark:mask`
* called from a callback resolve their path from the directory cache alone.
*
* @module fsnotify
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/dcache.h>
#include <linux/fsnotify_backend.h>
#include <linux/limits.h>
#include <linux/list.h>
#include <linux/mount.h>
#include <linux/namei.h>
#include <linux/path.h>
#include <linux/pid.h>
#include <linux/string.h>

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
	lunatik_object_t *object;
	struct list_head entry;
	unsigned int type;
	char pathname[];
} luafsnotify_mark_t;

typedef struct luafsnotify_kind_s {
	const char *name;
	unsigned int type;
} luafsnotify_kind_t;

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
static const lunatik_class_t luafsnotify_mark_class;

LUNATIK_PRIVATECHECKER(luafsnotify_check, luafsnotify_t *, &luafsnotify_class);

LUNATIK_PRIVATECHECKER(luafsnotify_checkmark, luafsnotify_mark_t *, &luafsnotify_mark_class);

LUNATIK_PRIVATECHECKER(luafsnotify_checkevent, luafsnotify_event_t *, &luafsnotify_event_class);

/* set while a callback is on this state's stack */
static const char luafsnotify_dispatching;

static inline void luafsnotify_setdispatching(lua_State *L, bool on)
{
	lua_pushboolean(L, on);
	lua_rawsetp(L, LUA_REGISTRYINDEX, &luafsnotify_dispatching);
}

/* the event's own task may hold the directory's i_rwsem, and a walk that leaves
 * the dcache takes it again, so from a callback the walk stays in the dcache */
static int luafsnotify_kernpath(lua_State *L, const char *pathname, struct path *path)
{
	unsigned int flags = LOOKUP_FOLLOW;

	lunatik_getregistry(L, &luafsnotify_dispatching);
	if (lua_toboolean(L, -1))
		flags |= LOOKUP_CACHED;
	lua_pop(L, 1);
	return kern_path(pathname, flags, path);
}

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

	luafsnotify_setdispatching(L, true);
	if (lua_pcall(L, 2, 0, 0) != LUA_OK) /* callback(mask, event) */
		pr_err_ratelimited("%s\n", lua_tostring(L, -1));
	luafsnotify_setdispatching(L, false);

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

/* the registry holds the handle while the watch holds the mark, so a script may
 * drop it and find it again */
static inline void luafsnotify_bind(lua_State *L, int ix, lunatik_object_t *object, luafsnotify_mark_t *mark)
{
	object->private = mark;
	mark->object = object;
	lunatik_register(L, ix, mark);
}

static inline void luafsnotify_unbind(lua_State *L, luafsnotify_mark_t *mark)
{
	if (mark->object != NULL) /* NULL once the handle was collected */
		mark->object->private = NULL; /* the record goes with the mark: a stale handle raises */
	if (L != NULL) /* NULL on the release path, where the state is going away */
		lunatik_unregister(L, mark);
}

static void luafsnotify_removemark(lua_State *L, luafsnotify_mark_t *mark)
{
	struct fsnotify_group *group = mark->mark.group;

	luafsnotify_unbind(L, mark);
	list_del(&mark->entry);
	fsnotify_destroy_mark(&mark->mark, group);
	fsnotify_put_mark(&mark->mark); /* the reference fsnotify_init_mark left us */
}

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

	lua_State *L = lunatik_getstate(watch->runtime); /* NULL once the runtime is closing */
	list_for_each_entry_safe(mark, next, &watch->marks, entry)
		luafsnotify_removemark(L, mark);
	fsnotify_put_group(group);
}

static void luafsnotify_release(void *private)
{
	luafsnotify_detach((luafsnotify_t *)private);
}

/* from 6.10 the mark API takes the object itself; before that the object's
 * connector, and a mount's is reached through real_mount(), which fs/mount.h
 * keeps to the kernel, so there a mount cannot be marked at all */
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 10, 0))
#define LUAFSNOTIFY_KINDS	"\"inode\", \"mount\" or \"sb\""
#define luafsnotify_findmark(obj, type, group)	fsnotify_find_mark((obj), (type), (group))

static inline void *luafsnotify_object(const struct path *path, unsigned int type)
{
	switch (type) {
	case FSNOTIFY_OBJ_TYPE_VFSMOUNT:
		return path->mnt;
	case FSNOTIFY_OBJ_TYPE_SB:
		return path->mnt->mnt_sb;
	default:
		return d_inode(path->dentry);
	}
}
#else
#define LUAFSNOTIFY_KINDS	"\"inode\" or \"sb\""
#define luafsnotify_findmark(obj, type, group)	fsnotify_find_mark((obj), (group))

static inline fsnotify_connp_t *luafsnotify_object(const struct path *path, unsigned int type)
{
	return type == FSNOTIFY_OBJ_TYPE_SB ? &path->mnt->mnt_sb->s_fsnotify_marks :
		&d_inode(path->dentry)->i_fsnotify_marks;
}
#endif

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0))
#define luafsnotify_addmark(mark, obj, type)	fsnotify_add_mark((mark), (obj), (type), 0)
#else
#define luafsnotify_addmark(mark, obj, type)	fsnotify_add_mark((mark), (obj), (type), 0, NULL) /* no fsid */
#endif

static const luafsnotify_kind_t luafsnotify_kinds[] = {
	{"inode", FSNOTIFY_OBJ_TYPE_INODE},
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 10, 0))
	{"mount", FSNOTIFY_OBJ_TYPE_VFSMOUNT},
#endif
	{"sb", FSNOTIFY_OBJ_TYPE_SB},
};

static unsigned int luafsnotify_checkkind(lua_State *L, int ix)
{
	const char *kind = luaL_optstring(L, ix, "inode");
	size_t i;

	for (i = 0; i < ARRAY_SIZE(luafsnotify_kinds); i++)
		if (strcmp(kind, luafsnotify_kinds[i].name) == 0)
			return luafsnotify_kinds[i].type;
#if (LINUX_VERSION_CODE < KERNEL_VERSION(6, 10, 0))
	if (strcmp(kind, "mount") == 0)
		return luaL_argerror(L, ix, "\"mount\" needs a 6.10 kernel");
#endif
	return luaL_argerror(L, ix, "expected " LUAFSNOTIFY_KINDS);
}

static luafsnotify_mark_t *luafsnotify_attachmark(lua_State *L, luafsnotify_t *watch, const char *pathname,
	__u32 mask, unsigned int type)
{
	size_t len = strlen(pathname);
	luafsnotify_mark_t *mark = (luafsnotify_mark_t *)lunatik_checkzalloc(L, sizeof(luafsnotify_mark_t) + len + 1);
	struct path path;
	int ret;

	if ((ret = luafsnotify_kernpath(L, pathname, &path)) != 0) {
		lunatik_free(mark);
		lunatik_throw(L, ret);
	}

	memcpy(mark->pathname, pathname, len);
	mark->type = type;
	fsnotify_init_mark(&mark->mark, watch->group);
	mark->mark.mask = mask;
	/* the ignore mask is the script's: the next write to the object must not clear it */
	mark->mark.flags |= FSNOTIFY_MARK_FLAG_IGNORED_SURV_MODIFY;

	ret = luafsnotify_addmark(&mark->mark, luafsnotify_object(&path, type), type);
	path_put(&path);

	if (ret != 0) {
		fsnotify_put_mark(&mark->mark); /* frees through free_mark */
		lunatik_throw(L, ret);
	}

	list_add(&mark->entry, &watch->marks);
	return mark;
}

/***
* Places a mark on a filesystem object.
* Resolves `path` and marks what `kind` names for the events in `mask`: the
* inode it resolves to, the mount it is on, or its whole filesystem. An inode
* mark on a directory reports events on the files directly inside it only when
* `mask` carries `linux.fs.EVENT_ON_CHILD`, and never on anything deeper; a
* mount or superblock mark reports every file it covers without it.
* @function mark
* @tparam string path path of the object to mark
* @tparam integer mask event mask, a combination of `linux.fs` bits
* @tparam[opt] string kind `"inode"` (default), `"mount"` or `"sb"`; `"mount"`
*   needs a 6.10 kernel
* @treturn fsnotify_mark the mark, which the watch keeps until it is removed
* @raise if `path` does not resolve, `EAGAIN` when it is resolved from a
*   callback and is not in the directory cache, if `kind` is not one this kernel
*   offers, if this watch already marks the object, if the watch has been
*   stopped, or if `mask` carries a permission event
* @usage local mark = watch:mark("/tmp/scratch", fs.OPEN | fs.MODIFY, "mount")
*/
static int luafsnotify_mark(lua_State *L)
{
	luafsnotify_t *watch = luafsnotify_check(L, 1);
	const char *pathname = luaL_checkstring(L, 2);
	__u32 mask = (__u32)luaL_checkinteger(L, 3);
	unsigned int type = luafsnotify_checkkind(L, 4);

	/* the verdict such an event asks for is not implemented */
	luaL_argcheck(L, !(mask & ALL_FSNOTIFY_PERM_EVENTS), 3, "permission events not supported");

	lunatik_object_t *object = lunatik_newobject(L, &luafsnotify_mark_class, 0, LUNATIK_OPT_NONE);
	luafsnotify_mark_t *mark = luafsnotify_attachmark(L, watch, pathname, mask, type);

	luafsnotify_bind(L, -1, object, mark);
	return 1; /* object */
}

/***
* Finds the mark this watch placed on an object.
* Resolves `path` and asks the kernel, which keys the marks by the object they
* are on, so a script does not have to keep a table of its own.
* @function find
* @tparam string path path of the marked object
* @tparam[opt] string kind `"inode"` (default), `"mount"` or `"sb"`; `"mount"`
*   needs a 6.10 kernel
* @treturn fsnotify_mark the mark this watch placed there, or `nil` when it has
*   none
* @raise if `path` does not resolve, `EAGAIN` when it is resolved from a
*   callback and is not in the directory cache, if `kind` is not one this kernel
*   offers, or if the watch has been stopped
* @usage local mark = watch:find("/tmp/scratch", "mount")
*/
static int luafsnotify_find(lua_State *L)
{
	luafsnotify_t *watch = luafsnotify_check(L, 1);
	const char *pathname = luaL_checkstring(L, 2);
	unsigned int type = luafsnotify_checkkind(L, 3);
	struct fsnotify_mark *found;
	struct path path;
	int ret;

	if ((ret = luafsnotify_kernpath(L, pathname, &path)) != 0)
		lunatik_throw(L, ret);

	found = luafsnotify_findmark(luafsnotify_object(&path, type), type, watch->group);
	path_put(&path);

	if (found == NULL) {
		lua_pushnil(L);
		return 1;
	}

	lunatik_getregistry(L, container_of(found, luafsnotify_mark_t, mark)); /* push the handle */
	fsnotify_put_mark(found); /* the reference fsnotify_find_mark took */
	return 1;
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
* A mark on a filesystem object.
* A userdata `watch:mark` returns and `watch:find` hands back. The watch owns
* the mark: dropping the handle leaves the mark in place, and `watch:stop`
* removes every mark the watch placed. A handle whose mark is gone raises.
* @type fsnotify_mark
*/

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 0, 0))
#define luafsnotify_ignoremask(mark)	((mark)->mark.ignore_mask)
#else
#define luafsnotify_ignoremask(mark)	((mark)->mark.ignored_mask) /* renamed in 6.0 */
#endif

/***
* Reads the mark's event mask, or sets it.
* Setting it removes the mark and adds it again, because the mask an object is
* watched for is a sum over its marks that only the kernel's own add
* recalculates: `path` is resolved once more, and an event in between is not
* reported. The handle stays the same.
* @function mask
* @tparam[opt] integer mask the new event mask, a combination of `linux.fs` bits
* @treturn integer the mark's event mask
* @raise if the mark has been removed, if `mask` carries a permission event, or
*   if the mark cannot be added again, because the path no longer resolves, is
*   not in the directory cache of a callback resolving it, or the kernel refuses
*   it, which leaves the mark removed
* @usage mark:mask(mark:mask() | fs.MODIFY)
*/
static int luafsnotify_mask(lua_State *L)
{
	luafsnotify_mark_t *mark = luafsnotify_checkmark(L, 1);

	if (!lua_isnoneornil(L, 2)) {
		__u32 mask = (__u32)luaL_checkinteger(L, 2);
		luafsnotify_t *watch = (luafsnotify_t *)mark->mark.group->private; /* the mark holds the group */
		lunatik_object_t *object = mark->object;
		unsigned int type = mark->type;

		luaL_argcheck(L, !(mask & ALL_FSNOTIFY_PERM_EVENTS), 2, "permission events not supported");

		const char *pathname = lua_pushstring(L, mark->pathname); /* the record goes with the mark */

		luafsnotify_removemark(L, mark);
		mark = luafsnotify_attachmark(L, watch, pathname, mask, type);
		luafsnotify_bind(L, 1, object, mark); /* index 1 is the handle this method was called on */
	}

	lua_pushinteger(L, (lua_Integer)mark->mark.mask);
	return 1;
}

/***
* Reads the mark's ignore mask, or sets it.
* An event in the ignore mask is not reported through this mark, whatever its
* event mask carries, and the ignore mask a script sets holds until it sets
* another: a write to the object does not clear it.
* @function ignore
* @tparam[opt] integer mask the events to ignore, a combination of `linux.fs` bits
* @treturn integer the mark's ignore mask
* @raise if the mark has been removed
* @usage mark:ignore(fs.OPEN)
*/
static int luafsnotify_ignore(lua_State *L)
{
	luafsnotify_mark_t *mark = luafsnotify_checkmark(L, 1);

	if (!lua_isnoneornil(L, 2))
		luafsnotify_ignoremask(mark) = (__u32)luaL_checkinteger(L, 2);

	lua_pushinteger(L, (lua_Integer)luafsnotify_ignoremask(mark));
	return 1;
}

/***
* Removes the mark.
* No further event reaches the callback through it, and the watch drops it.
* @function remove
* @treturn nil
* @raise if the mark has already been removed
* @usage mark:remove()
*/
static int luafsnotify_remove(lua_State *L)
{
	luafsnotify_mark_t *mark = luafsnotify_checkmark(L, 1);

	luafsnotify_removemark(L, mark);
	return 0;
}

static void luafsnotify_releasemark(void *private)
{
	((luafsnotify_mark_t *)private)->object = NULL; /* the watch keeps the mark the handle leaves */
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
	{"find", luafsnotify_find},
	{"mark", luafsnotify_mark},
	{"stop", luafsnotify_stop},
	{NULL, NULL}
};

static const luaL_Reg luafsnotify_mark_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"ignore", luafsnotify_ignore},
	{"mask", luafsnotify_mask},
	{"remove", luafsnotify_remove},
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

static const lunatik_class_t luafsnotify_mark_class = {
	.name = "fsnotify.mark",
	.methods = luafsnotify_mark_mt,
	.release = luafsnotify_releasemark,
	.opt = LUNATIK_OPT_SINGLE | LUNATIK_OPT_EXTERNAL,
};

LUNATIK_CLASSES(fsnotify, &luafsnotify_class, &luafsnotify_event_class, &luafsnotify_mark_class);
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

