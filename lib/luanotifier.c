/*
* SPDX-FileCopyrightText: (c) 2023-2026 Ring Zero Desenvolvimento de Software LTDA
* SPDX-License-Identifier: MIT OR GPL-2.0-only
*/

/***
* Notifier chain mechanism.
* This library allows Lua scripts to register callback functions that are
* invoked when specific kernel events occur, such as keyboard input,
* network device status changes, or virtual terminal events.
* A `keyboard` or `vt` callback returns a `linux.notify` code; anything else, a
* callback that raises, which is logged, and an event that reaches a runtime not
* ready to take it, or that the runtime's own code raises from under its lock,
* counts as `notify.DONE`. A `netdevice` callback runs after its event, and what
* it returns is ignored.
*
* @module notifier
*/

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt
#include <linux/netdevice.h>
#include <linux/sched.h>
#include <linux/llist.h>
#include <linux/wait_bit.h>
#ifdef CONFIG_VT
#include <linux/keyboard.h>
#include <linux/vt_kern.h>
#include <linux/vt.h>
#endif

#include <lunatik.h>

typedef int (*luanotifier_register_t)(struct notifier_block *nb);
typedef int (*luanotifier_handler_t)(lua_State *L, unsigned long event, void *data);

/***
* Represents a kernel notifier object.
* This is a userdata object returned by functions like `notifier.keyboard()`,
* `notifier.netdevice()`, or `notifier.vt()`. It encapsulates a
* `struct notifier_block` and the associated Lua callback.
* @type notifier
*/

typedef struct luanotifier_s {
	struct notifier_block nb;
	lunatik_object_t *runtime;
	luanotifier_handler_t handler;
	luanotifier_register_t unregister;
	struct task_struct *registrant;
	lunatik_object_t *object;
	struct llist_head events;
	lunatik_defer_t defer;
} luanotifier_t;

typedef struct luanotifier_event_s {
	struct llist_node entry;
	unsigned long event;
	unsigned int netns;
	int ifindex;
	bool replayed;
	char name[IFNAMSIZ];
} luanotifier_event_t;

static const lunatik_class_t luanotifier_process_class;
static const lunatik_class_t luanotifier_hardirq_class;

LUNATIK_PRIVATECHECKERS(luanotifier_check, luanotifier_t *, "notifier", &luanotifier_process_class,
	&luanotifier_hardirq_class);

/* an event delivered inside register_fn, on the task that registered the block */
#define luanotifier_isreplay(notifier)	((notifier)->registrant == current)

typedef struct luanotifier_ctx_s {
	luanotifier_t *notifier;
	unsigned long event;
	void *data;
	int ret;
} luanotifier_ctx_t;

static int luanotifier_docall(lua_State *L)
{
	luanotifier_ctx_t *ctx = lua_touserdata(L, 1);
	luanotifier_t *notifier = ctx->notifier;

	if (lunatik_getregistry(L, notifier) != LUA_TFUNCTION)
		return 0; /* callback removed by stop() — silent no-op */

	lua_pushinteger(L, (lua_Integer)ctx->event);

	int nargs = notifier->handler(L, ctx->event, ctx->data);
	lua_call(L, nargs + 1, 1); /* callback(event, ...) */
	ctx->ret = lua_tointeger(L, -1);
	return 0;
}

static int luanotifier_call(struct notifier_block *nb, unsigned long event, void *data)
{
	luanotifier_t *notifier = container_of(nb, luanotifier_t, nb);
	luanotifier_ctx_t ctx = {.notifier = notifier, .event = event, .data = data, .ret = NOTIFY_DONE};
	int ret;

	lunatik_run(notifier->runtime, lunatik_catch, ret, luanotifier_docall, &ctx, "callback");
	(void)ret; /* not ready, under its own lock or raised: the callback returned nothing */
	return max(ctx.ret, NOTIFY_DONE); /* a negative return would set NOTIFY_STOP_MASK */
}

static void luanotifier_release(void *private)
{
	luanotifier_t *notifier = (luanotifier_t *)private;

	/* release runs from lua_close or the drain's last put, in process context, where unregister may sleep */
	if (notifier->unregister)
		notifier->unregister(&notifier->nb);
	if (notifier->runtime) /* NULL if checkruntime errored in init */
		lunatik_putobject(notifier->runtime);
}

/***
* Stops event delivery to the Lua callback.
* After `stop()`, the underlying `notifier_block` remains registered in the
* kernel chain until the owning runtime is torn down, but firings become
* silent no-ops. This keeps `stop()` safe in any context (including hardirq)
* since it performs no sleeping operations; the real unregistration happens
* in `release`, which always runs in process context. A to-be-closed variable
* holding the notifier stops it the same way.
* @function stop
* @treturn nil
* @usage my_notifier:stop()
*/
static int luanotifier_stop(lua_State *L)
{
	luanotifier_t *notifier = luanotifier_check(L, 1);

	lunatik_unregister(L, notifier); /* clear callback; handler becomes no-op */
	return 0;
}

static int luanotifier_new(lua_State *, luanotifier_register_t, luanotifier_register_t,
	luanotifier_handler_t, notifier_fn_t, const lunatik_class_t *);

#define LUANOTIFIER_NEWCHAIN(name, class)					\
static int luanotifier_##name(lua_State *L)					\
{										\
	return luanotifier_new(L, register_##name##_notifier,			\
		unregister_##name##_notifier, luanotifier_##name##_handler,	\
		luanotifier_call, (class));					\
}

static int luanotifier_netdevice_handler(lua_State *L, unsigned long event, void *data)
{
	luanotifier_event_t *queued = (luanotifier_event_t *)data;

	lua_pushstring(L, queued->name);
	lua_pushinteger(L, queued->netns);
	lua_pushboolean(L, queued->replayed);
	lua_pushinteger(L, queued->ifindex);
	return 4;
}

static int luanotifier_netdevice_call(struct notifier_block *nb, unsigned long event, void *data)
{
	luanotifier_t *notifier = container_of(nb, luanotifier_t, nb);
	struct net_device *dev = netdev_notifier_info_to_dev(data);
	luanotifier_event_t *queued = kmalloc(sizeof(luanotifier_event_t), GFP_KERNEL);

	if (queued == NULL) {
		pr_err_ratelimited("couldn't queue event %lu of %s\n", event, dev->name);
		return NOTIFY_DONE;
	}
	if (!lunatik_trygetobject(notifier->object)) {
		kfree(queued);
		return NOTIFY_DONE;
	}

	queued->event = event;
	queued->netns = dev_net(dev)->ns.inum;
	queued->ifindex = dev->ifindex;
	queued->replayed = luanotifier_isreplay(notifier);
	strscpy(queued->name, dev->name, IFNAMSIZ);

	if (llist_add(&queued->entry, &notifier->events))
		lunatik_defer(&notifier->defer);
	return NOTIFY_DONE;
}

/* the script body returned, armed or not */
#define luanotifier_isloaded(runtime)	(lunatik_isready(runtime) || lunatik_isclosing(runtime))

static void luanotifier_drain(struct work_struct *work)
{
	luanotifier_t *notifier = container_of(work, luanotifier_t, defer.work);
	lunatik_object_t *runtime = notifier->runtime;
	lunatik_object_t *object = notifier->object;
	struct llist_node *events = llist_reverse_order(llist_del_all(&notifier->events));
	luanotifier_event_t *queued, *next;

	wait_var_event(runtime, luanotifier_isloaded(runtime));
	llist_for_each_entry_safe(queued, next, events, entry) {
		luanotifier_call(&notifier->nb, queued->event, queued);
		kfree(queued);
		lunatik_putobject(object);
	}
}

/***
* Registers a network-device notifier. Must be called from a process
* runtime (the default). The devices of every network namespace are reported,
* each with the inode number of its namespace: `linux.ifindex` resolves a name
* in the initial namespace only, so a script keeps the devices that name
* resolves by comparing that number with `linux.netns()`. The callback runs
* after the event, off RTNL, on a kernel worker that takes the runtime's lock,
* once per event and in the order the events came; what it returns is ignored,
* so it cannot veto one. A thread body of the runtime holds that lock while it
* runs, so the callback waits for the body to return, and the worker with it: a
* body that runs longer than `hung_task_timeout_secs` leaves the worker reported
* as a hung task until it returns. An event that finds no memory to be queued is
* logged and dropped.
*
* @function netdevice
* @tparam function callback invoked as `callback(event, name, netns, replayed, ifindex)` —
*   `event` is a `linux.netdev` code, `name` is the device name (e.g. `"eth0"`) and `netns`
*   the inode number of its network namespace, as `linux.netns` gives it, both read when the
*   event happened, so the device may be renamed or gone when the callback runs; `ifindex`
*   is the device's index, which a rename keeps, so it names the device whatever its name
*   is by then; `replayed` is true for an event the registration replays: a `REGISTER` for
*   each device every namespace already has, and an `UP` for each of those that is up. They
*   reach the callback after the code that registered returns, the script body included.
* @treturn notifier the notifier, which this call keeps for its runtime: dropping it
*   stops nothing, and the callback runs until `stop` or the end of the runtime
* @raise if called from a percpu runtime;
*   `'notifier': process-context class in interrupt-context runtime` in a softirq or hardirq
*   runtime; `not allowed while the runtime closes` from a finalizer that runs at its close;
*   the kernel's errno when it refuses the registration
* @within notifier
*/
static int luanotifier_netdevice(lua_State *L)
{
	return luanotifier_new(L, register_netdevice_notifier, unregister_netdevice_notifier,
		luanotifier_netdevice_handler, luanotifier_netdevice_call, &luanotifier_process_class);
}

#ifdef CONFIG_VT
static int luanotifier_keyboard_handler(lua_State *L, unsigned long event, void *data)
{
	struct keyboard_notifier_param *param = (struct keyboard_notifier_param *)data;

	lua_pushboolean(L, param->down);
	lua_pushboolean(L, param->shift);
	lua_pushinteger(L, (lua_Integer)(param->value));
	return 3;
}

/***
* Registers a keyboard-event notifier. Must be called from a `hardirq` runtime.
*
* @function keyboard
* @tparam function callback invoked as `callback(event, down, shift, value)`
*   — `event` is a `linux.kbd` code, `down` is a boolean (key pressed),
*   `shift` is a boolean (modifier held), and `value` is the keycode or
*   keysym depending on `event`. Returns a `linux.notify` status code.
* @treturn notifier the notifier, which this call keeps for its runtime: dropping it
*   stops nothing, and the callback runs until `stop` or the end of the runtime
* @raise `EOPNOTSUPP` on a kernel built without `CONFIG_VT`;
*   if called from a percpu runtime; `runtime context mismatch` outside a hardirq runtime;
*   `not allowed while the runtime closes` from a finalizer that runs at its close;
*   the kernel's errno when it refuses the registration
* @within notifier
*/
LUANOTIFIER_NEWCHAIN(keyboard,  &luanotifier_hardirq_class);

/* vc_allocate and vc_deallocate leave c uninitialized */
#define luanotifier_iswrite(event)	((event) == VT_WRITE || (event) == VT_PREWRITE)

static int luanotifier_vt_handler(lua_State *L, unsigned long event, void *data)
{
	struct vt_notifier_param *param = data;

	lunatik_pushoptinteger(L, luanotifier_iswrite(event), param->c);
	lua_pushinteger(L, param->vc->vc_num);
	return 2;
}

/***
* Registers a virtual-terminal notifier. Must be called from a `hardirq` runtime.
*
* @function vt
* @tparam function callback invoked as `callback(event, c, vc_num)` —
*   `event` is a `linux.vt` code, `c` is the character value a `WRITE` or
*   `PREWRITE` carries and nil for any other event, and `vc_num` is the
*   virtual console number. Returns a `linux.notify` status code.
* @treturn notifier the notifier, which this call keeps for its runtime: dropping it
*   stops nothing, and the callback runs until `stop` or the end of the runtime
* @raise `EOPNOTSUPP` on a kernel built without `CONFIG_VT`;
*   if called from a percpu runtime; `runtime context mismatch` outside a hardirq runtime;
*   `not allowed while the runtime closes` from a finalizer that runs at its close;
*   the kernel's errno when it refuses the registration
* @within notifier
*/
LUANOTIFIER_NEWCHAIN(vt, &luanotifier_hardirq_class);
#else
#define luanotifier_keyboard	lunatik_unsupported
#define luanotifier_vt		lunatik_unsupported
#endif

static const luaL_Reg luanotifier_lib[] = {
	{"netdevice", luanotifier_netdevice},
	{"keyboard", luanotifier_keyboard},
	{"vt", luanotifier_vt},
	{NULL, NULL}
};

static const luaL_Reg luanotifier_mt[] = {
	{"__gc", lunatik_deleteobject},
	{"__close", luanotifier_stop},
	{"stop", luanotifier_stop},
	{NULL, NULL}
};

static const lunatik_class_t luanotifier_process_class = {
	.name = "notifier",
	.methods = luanotifier_mt,
	.release = luanotifier_release,
	.opt = LUNATIK_OPT_SINGLE,
	.owner = THIS_MODULE,
};

static const lunatik_class_t luanotifier_hardirq_class = {
	.name = "notifier",
	.methods = luanotifier_mt,
	.release = luanotifier_release,
	.opt = LUNATIK_OPT_HARDIRQ | LUNATIK_OPT_SINGLE,
	.owner = THIS_MODULE,
};

static int luanotifier_new(lua_State *L, luanotifier_register_t register_fn, luanotifier_register_t unregister_fn,
	luanotifier_handler_t handler_fn, notifier_fn_t call_fn, const lunatik_class_t *class)
{
	lunatik_checkpercpu(L);
	luaL_checktype(L, 1, LUA_TFUNCTION); /* callback */

	lunatik_object_t *object = lunatik_newobject(L, class, sizeof(luanotifier_t), LUNATIK_OPT_NONE);
	luanotifier_t *notifier = (luanotifier_t *)object->private;

	notifier->runtime = lunatik_checkruntime(L, class->name, class->opt);
	lunatik_getobject(notifier->runtime);

	notifier->nb.notifier_call = call_fn;
	notifier->handler = handler_fn;
	notifier->object = object;
	init_llist_head(&notifier->events);
	lunatik_initdefer(&notifier->defer, luanotifier_drain);

	lunatik_registerobject(L, 1, object);

	notifier->registrant = current; /* the replay register_fn delivers runs on this task */
	int err = register_fn(&notifier->nb);
	notifier->registrant = NULL;
	if (err != 0) {
		lunatik_unregisterobject(L, object);
		lunatik_throw(L, err);
	}

	notifier->unregister = unregister_fn; /* release skips a block register_fn did not take */
	return 1; /* object */
}

LUNATIK_CLASSES(notifier, &luanotifier_process_class, &luanotifier_hardirq_class);
LUNATIK_NEWLIB(notifier, luanotifier_lib, luanotifier_classes);

static int __init luanotifier_init(void)
{
	return 0;
}

static void __exit luanotifier_exit(void)
{
	lunatik_flushdefer();
}

module_init(luanotifier_init);
module_exit(luanotifier_exit);
MODULE_LICENSE("Dual MIT/GPL");
MODULE_VERSION(LUNATIK_RELEASE);
MODULE_AUTHOR("Lourival Vieira Neto <lourival.neto@ringzero.com.br>");

