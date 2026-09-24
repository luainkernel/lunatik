# Kernel notes: release context

Every fact the plan rests on, linked at a pinned tag or commit. Lunatik is read at master
`c616f820e5a901275aca04dc41c9ec0d5c4dc6ed`, the Lua fork at `74f1f100cb58a23b4ff7625a99715394540beba9`,
the kernel at v6.6 and v7.2, the ends of the range CI builds, and at v6.8, the host these notes were
written on, with the tags in between where a path changed. Exports were checked in `Module.symvers`
of `linux-headers-6.8.0-138-generic`. Re-check on the kernel you target.

## Lunatik: where a put runs its release

| Fact | Where |
|------|-------|
| `lunatik_putobject` is `kref_put(&kref, lunatik_releaseobject)` | [lunatik.h#L278](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik.h#L278) |
| `lunatik_releaseobject` runs the class release in place when the private is set | [lunatik_obj.c#L106-L117](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_obj.c#L106-L117) |
| `lunatik_closeprivate` releases the private under the object lock, so a later put frees only | [lunatik_obj.c#L85-L97](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_obj.c#L85-L97) |
| `lunatik_deleteobject`, every class's `__gc`, refuses a call that is not the collector's and puts | [lunatik_obj.c#L119-L135](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_obj.c#L119-L135) |
| `lunatik_monitor` stops the collector around a monitored method and restarts it after, unconditionally | [lunatik_obj.c#L148-L167](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_obj.c#L148-L167) |
| the runtime's release is `lua_close` | [lunatik_core.c#L80-L84](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_core.c#L80-L84) |
| `lunatik_stop` closes the private, then puts | [lunatik_core.c#L86-L91](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_core.c#L86-L91) |
| `runtime:stop()` and `__close` refuse under RTNL, then close in place | [lunatik_core.c#L188-L207](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_core.c#L188-L207) |
| `lunatik_rtnl`, `lunatik_setrtnl`, `lunatik_isrtnl`, `lunatik_checkrtnl` | [lunatik_core.c#L31](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_core.c#L31), [lunatik.h#L214-L221](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik.h#L214-L221) |
| the class options, seven of eight bits used | [lunatik.h#L22-L30](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik.h#L22-L30) |
| `lunatik_object_t` | [lunatik.h#L80-L92](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik.h#L80-L92) |
| a SOFTIRQ class locks with `spin_lock_bh`, or `spin_lock_irqsave` with IRQs already off | [lunatik_lock.h#L29-L38](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_lock.h#L29-L38) |
| `lunatik.runtime()` hands back the one reference; the failure path closes in place with the private NULL | [lunatik_core.c#L287-L293](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_core.c#L287-L293), [#L329-L339](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_core.c#L329-L339) |
| `lunatik_runscript` pushes `lunatik_env` into every new state | [lunatik_core.c#L243-L246](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_core.c#L243-L246) |
| `lunatik_exit` does nothing; `lunatik_run_exit` puts the env and stops the driver | [lunatik_core.c#L352-L354](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_core.c#L352-L354), [lunatik_run.c#L32-L36](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_run.c#L32-L36) |
| the CLI unloads with `runner.shutdown()` then removes every module at refcount 0 until a pass removes none | [bin/lunatik#L71-L89](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/bin/lunatik#L71-L89) |

### The puts that are not a stop

| Put | Where |
|-----|-------|
| an `rcu.table` value is any shareable object | [lunatik_val.c#L8-L27](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_val.c#L8-L27) |
| `luarcu_free` puts the value; `luarcu_setvalue` calls it under the table lock | [luarcu.c#L93-L98](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luarcu.c#L93-L98), [#L122-L153](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luarcu.c#L122-L153) |
| every `rcu.table` is a SOFTIRQ class | [luarcu.c#L290-L296](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luarcu.c#L290-L296) |
| the thread body puts its runtime and itself when it ends, on the kthread | [luathread.c#L47-L58](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luathread.c#L47-L58) |
| `thread:stop()` runs `kthread_stop` and, on `-EINTR`, puts on the caller | [luathread.c#L85-L111](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luathread.c#L85-L111) |
| `thread.run` takes a reference on the runtime | [luathread.c#L237-L242](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luathread.c#L237-L242) |
| a percpu object's release puts each runtime, "a put, never a stop" | [lunatik_percpu.c#L89-L101](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_percpu.c#L89-L101) |
| the shared data holds the percpu object, so a set with data outstanding is released by `stop` only | [lunatik_percpu.c#L32-L44](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lunatik_percpu.c#L32-L44) |
| a device file's last close puts the runtime; the runtime's state was closed by its stop | [luadevice.c#L70-L77](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luadevice.c#L70-L77), [#L210-L216](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luadevice.c#L210-L216) |
| `runner.stop` stops the item before it clears the entry | [runner.lua#L38-L43](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/lunatik/runner.lua#L38-L43) |

### The releases, and what pins each to `lua_close`

| Class | Release | Pin |
|-------|---------|-----|
| socket: `kernel_sock_shutdown`, `sock_release` | [luasocket.c#L477-L482](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luasocket.c#L477-L482) | none; `close` and `__close` are `lunatik_closeobject` ([#L489-L502](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luasocket.c#L489-L502)) |
| socket: the RTNL refusals #1045 added, on send, receive and `setsockopt` past `SOL_SOCKET` | [luasocket.c#L138-L142](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luasocket.c#L138-L142), [#L437-L447](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luasocket.c#L437-L447) | `bind` has none ([#L296-L306](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luasocket.c#L296-L306)) |
| notifier: `unregister_*_notifier`, then the runtime's put; the comment states the premise | [luanotifier.c#L90-L100](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanotifier.c#L90-L100) | holds its runtime and its registry slot ([#L275-L281](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanotifier.c#L275-L281)) |
| notifier: the netdevice dispatch sets and restores `lunatik_rtnl` | [luanotifier.c#L145-L152](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanotifier.c#L145-L152) | |
| netlink.channel: `genl_unregister_family` | [luanetlink.c#L37-L43](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanetlink.c#L37-L43) | its registry slot ([#L174](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanetlink.c#L174)); the constructor has `lunatik_checkarmed` and no RTNL check ([#L153-L176](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanetlink.c#L153-L176)) |
| netfilter: `nf_unregister_net_hook` | [luanetfilter.c#L142-L145](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanetfilter.c#L142-L145), [#L230-L239](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanetfilter.c#L230-L239) | [#L178](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanetfilter.c#L178), [#L220](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luanetfilter.c#L220) |
| probe | [luaprobe.c#L217-L226](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luaprobe.c#L217-L226) | [#L362](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luaprobe.c#L362), [#L383](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luaprobe.c#L383) |
| fsnotify | [luafsnotify.c#L218-L230](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luafsnotify.c#L218-L230) | [#L668-L670](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luafsnotify.c#L668-L670), [#L714](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luafsnotify.c#L714) |
| hid | [luahid.c#L42-L56](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luahid.c#L42-L56) | [#L305-L307](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luahid.c#L305-L307) |
| device | [luadevice.c#L243-L250](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luadevice.c#L243-L250) | [#L377](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luadevice.c#L377), [#L388](https://github.com/luainkernel/lunatik/blob/c616f820e5a901275aca04dc41c9ec0d5c4dc6ed/lib/luadevice.c#L388) |

## The Lua fork: when a finalizer runs

| Fact | Where |
|------|-------|
| every allocation may run a collector step | [lgc.h#L233-L238](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lgc.h#L233-L238) |
| a step calls one finalizer at a time, in the incremental cycle's `GCScallfin` state, unless an emergency collection | [lgc.c#L1669-L1681](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lgc.c#L1669-L1681) |
| `GCTM` marks the frame with `CIST_FIN`, which `lunatik_deleteobject` reads | [lgc.c#L968-L990](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lgc.c#L968-L990) |
| `lua_close` runs every pending finalizer, then frees the rest | [lstate.c#L260-L270](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lstate.c#L260-L270), [lgc.c#L1529-L1540](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lgc.c#L1529-L1540) |
| `lua_gc(L, LUA_GCSTOP)` sets `GCSTPUSR`; `LUA_GCRESTART` clears every stop bit, so a nested restart re-enables an outer stop | [lapi.c#L1184-L1191](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lapi.c#L1184-L1191), [lgc.c#L1740-L1746](https://github.com/luainkernel/lua/blob/74f1f100cb58a23b4ff7625a99715394540beba9/lgc.c#L1740-L1746) |

## The netdevice chain and RTNL

| Fact | v6.6 | v6.8 | v7.2 |
|------|------|------|------|
| the chain runs under RTNL (`ASSERT_RTNL`) | [dev.c#L1980-L1987](https://github.com/torvalds/linux/blob/v6.6/net/core/dev.c#L1980-L1987) | [dev.c#L1951-L1958](https://github.com/torvalds/linux/blob/v6.8/net/core/dev.c#L1951-L1958) | [dev.c#L2235-L2242](https://github.com/torvalds/linux/blob/v7.2/net/core/dev.c#L2235-L2242) |
| `register_netdevice_notifier` takes `pernet_ops_rwsem` and RTNL and replays inside | [dev.c#L1764-L1784](https://github.com/torvalds/linux/blob/v6.6/net/core/dev.c#L1764-L1784) | [dev.c#L1735-L1755](https://github.com/torvalds/linux/blob/v6.8/net/core/dev.c#L1735-L1755) | [dev.c#L1968](https://github.com/torvalds/linux/blob/v7.2/net/core/dev.c#L1968) |
| `unregister_netdevice_notifier` takes both | [dev.c#L1811-L1827](https://github.com/torvalds/linux/blob/v6.6/net/core/dev.c#L1811-L1827) | [dev.c#L1782-L1798](https://github.com/torvalds/linux/blob/v6.8/net/core/dev.c#L1782-L1798) | [dev.c#L2023-L2031](https://github.com/torvalds/linux/blob/v7.2/net/core/dev.c#L2023-L2031) |

At v7.2 the unregistration also takes the per-namespace `__rtnl_net_lock`; the global lock stays, and
the chain still asserts it.

## Generic netlink: `cb_lock` and `genl_mutex`

| Fact | v6.6 | v6.8 | v7.2 |
|------|------|------|------|
| `cb_lock` is an rwsem, `genl_mutex` serializes families without `parallel_ops` | [genetlink.c#L25-L26](https://github.com/torvalds/linux/blob/v6.6/net/netlink/genetlink.c#L25-L26) | [genetlink.c#L25-L26](https://github.com/torvalds/linux/blob/v6.8/net/netlink/genetlink.c#L25-L26) | |
| `genl_lock_all`: `down_write(&cb_lock)` then `genl_lock()` | [#L43-L47](https://github.com/torvalds/linux/blob/v6.6/net/netlink/genetlink.c#L43-L47) | [#L43-L47](https://github.com/torvalds/linux/blob/v6.8/net/netlink/genetlink.c#L43-L47) | [#L45-L49](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L45-L49) |
| `genl_register_family` and `genl_unregister_family` take it | [#L645-L654](https://github.com/torvalds/linux/blob/v6.6/net/netlink/genetlink.c#L645-L654), [#L714-L716](https://github.com/torvalds/linux/blob/v6.6/net/netlink/genetlink.c#L714-L716) | [#L778-L787](https://github.com/torvalds/linux/blob/v6.8/net/netlink/genetlink.c#L778-L787), [#L853-L855](https://github.com/torvalds/linux/blob/v6.8/net/netlink/genetlink.c#L853-L855) | [#L775](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L775), [#L850](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L850) |
| `genl_rcv` holds `cb_lock` for reading across a request; `genl_rcv_msg` takes `genl_mutex` for a family without `parallel_ops` | [#L1072-L1076](https://github.com/torvalds/linux/blob/v6.6/net/netlink/genetlink.c#L1072-L1076), [#L1055-L1068](https://github.com/torvalds/linux/blob/v6.6/net/netlink/genetlink.c#L1055-L1068) | [#L1214-L1218](https://github.com/torvalds/linux/blob/v6.8/net/netlink/genetlink.c#L1214-L1218), [#L1197-L1210](https://github.com/torvalds/linux/blob/v6.8/net/netlink/genetlink.c#L1197-L1210) | [#L1215-L1219](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L1215-L1219), [#L1198](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L1198) |
| an ethtool `doit` takes RTNL under it | [ethtool/netlink.c#L370-L401](https://github.com/torvalds/linux/blob/v6.6/net/ethtool/netlink.c#L370-L401) | [ethtool/netlink.c#L370-L401](https://github.com/torvalds/linux/blob/v6.8/net/ethtool/netlink.c#L370-L401) | [ethtool/netlink.c#L507-L544](https://github.com/torvalds/linux/blob/v7.2/net/ethtool/netlink.c#L507-L544) |
| `genl_bind`, `down_read(&cb_lock)`, is the protocol's bind callback | [#L1670-L1676](https://github.com/torvalds/linux/blob/v6.6/net/netlink/genetlink.c#L1670-L1676), [#L1706](https://github.com/torvalds/linux/blob/v6.6/net/netlink/genetlink.c#L1706) | [#L1812-L1818](https://github.com/torvalds/linux/blob/v6.8/net/netlink/genetlink.c#L1812-L1818), [#L1851](https://github.com/torvalds/linux/blob/v6.8/net/netlink/genetlink.c#L1851) | [#L1811-L1817](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L1811-L1817) |
| `genl_unbind` and `genl_release`, both `down_read(&cb_lock)`, registered as the protocol's unbind and release | absent | absent | [#L1851-L1856](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L1851-L1856), [#L692-L697](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L692-L697), [#L1882-L1884](https://github.com/torvalds/linux/blob/v7.2/net/netlink/genetlink.c#L1882-L1884) |

`genl_release` arrives at v6.9, with the per-socket family private storage: [genetlink.c#L695-L701 at
v6.9](https://github.com/torvalds/linux/blob/v6.9/net/netlink/genetlink.c#L695-L701), registered at
[#L1882-L1884](https://github.com/torvalds/linux/blob/v6.9/net/netlink/genetlink.c#L1882-L1884). From
that tag every generic netlink socket's close takes `cb_lock` for reading, with or without a group.

### An rwsem reader queues behind a waiting writer

`rwsem_down_read_slowpath` refuses to steal the lock when it is owned by readers and a writer waits,
"to prevent a constant stream of readers from starving a sleeping writer":
[rwsem.c#L996-L1010 at v6.6](https://github.com/torvalds/linux/blob/v6.6/kernel/locking/rwsem.c#L996-L1010),
[v6.8](https://github.com/torvalds/linux/blob/v6.8/kernel/locking/rwsem.c#L996-L1010),
[v7.2#L1017-L1031](https://github.com/torvalds/linux/blob/v7.2/kernel/locking/rwsem.c#L1017-L1031). So a
`down_read(&cb_lock)` on the task that holds RTNL, while a genetlink reader waits on RTNL and a
family registration waits to write, is a three-task cycle; a `down_write` there is a two-task one.

## The netlink socket

| Fact | v6.6 | v6.8 | v7.2 |
|------|------|------|------|
| `netlink_release` runs the protocol's `unbind` for each group, and its `release`, when set | [af_netlink.c#L751-L778](https://github.com/torvalds/linux/blob/v6.6/net/netlink/af_netlink.c#L751-L778) | [af_netlink.c#L751-L778](https://github.com/torvalds/linux/blob/v6.8/net/netlink/af_netlink.c#L751-L778) | [af_netlink.c#L718-L745](https://github.com/torvalds/linux/blob/v7.2/net/netlink/af_netlink.c#L718-L745) |
| `netlink_bind` runs the protocol's bind for each group in `nl_groups` | [#L1004-L1051](https://github.com/torvalds/linux/blob/v6.6/net/netlink/af_netlink.c#L1004-L1051) | [#L1004-L1051](https://github.com/torvalds/linux/blob/v6.8/net/netlink/af_netlink.c#L1004-L1051) | |
| `NETLINK_ADD_MEMBERSHIP` runs the same bind | [#L1680-L1692](https://github.com/torvalds/linux/blob/v6.6/net/netlink/af_netlink.c#L1680-L1692) | [#L1678-L1690](https://github.com/torvalds/linux/blob/v6.8/net/netlink/af_netlink.c#L1678-L1690) | |
| rtnetlink's bind is a capability check for the mroute groups, with no unbind and no release | [rtnetlink.c#L6463-L6473](https://github.com/torvalds/linux/blob/v6.6/net/core/rtnetlink.c#L6463-L6473), [#L6515](https://github.com/torvalds/linux/blob/v6.6/net/core/rtnetlink.c#L6515) | [rtnetlink.c#L6638-L6648](https://github.com/torvalds/linux/blob/v6.8/net/core/rtnetlink.c#L6638-L6648), [#L6690](https://github.com/torvalds/linux/blob/v6.8/net/core/rtnetlink.c#L6690) | [rtnetlink.c#L7106-L7116](https://github.com/torvalds/linux/blob/v7.2/net/core/rtnetlink.c#L7106-L7116), [#L7157](https://github.com/torvalds/linux/blob/v7.2/net/core/rtnetlink.c#L7157) |
| `rtnetlink_rcv_msg` takes RTNL for a handler without `RTNL_FLAG_DOIT_UNLOCKED` (#1045's trace) | [#L6336-L6439](https://github.com/torvalds/linux/blob/v6.6/net/core/rtnetlink.c#L6336-L6439) | [#L6511-L6614](https://github.com/torvalds/linux/blob/v6.8/net/core/rtnetlink.c#L6511-L6614) | [#L6977-L7072](https://github.com/torvalds/linux/blob/v7.2/net/core/rtnetlink.c#L6977-L7072) |

So a `NETLINK_ROUTE` socket's close takes no lock on any kernel in the range, and a
`NETLINK_GENERIC` one's takes `cb_lock` for reading from v6.9.

## The socket releases that take RTNL

| Path | v6.6 | v6.8 | v7.2 |
|------|------|------|------|
| `inet_release` calls `ip_mc_drop_socket` | [af_inet.c#L409-L420](https://github.com/torvalds/linux/blob/v6.6/net/ipv4/af_inet.c#L409-L420) | [af_inet.c#L412-L423](https://github.com/torvalds/linux/blob/v6.8/net/ipv4/af_inet.c#L412-L423) | [af_inet.c#L418-L429](https://github.com/torvalds/linux/blob/v7.2/net/ipv4/af_inet.c#L418-L429) |
| `ip_mc_drop_socket`: returns on an empty `mc_list`, else `rtnl_lock()` | [igmp.c#L2690-L2700](https://github.com/torvalds/linux/blob/v6.6/net/ipv4/igmp.c#L2690-L2700) | [igmp.c#L2692-L2702](https://github.com/torvalds/linux/blob/v6.8/net/ipv4/igmp.c#L2692-L2702) | [igmp.c#L2814-L2824](https://github.com/torvalds/linux/blob/v7.2/net/ipv4/igmp.c#L2814-L2824) |
| `inet6_release` calls `ipv6_sock_mc_close` and `ipv6_sock_ac_close` | [af_inet6.c#L471-L482](https://github.com/torvalds/linux/blob/v6.6/net/ipv6/af_inet6.c#L471-L482) | [af_inet6.c#L475-L486](https://github.com/torvalds/linux/blob/v6.8/net/ipv6/af_inet6.c#L475-L486) | [af_inet6.c#L459-L470](https://github.com/torvalds/linux/blob/v7.2/net/ipv6/af_inet6.c#L459-L470) |
| `ipv6_sock_mc_close`: returns on an empty `ipv6_mc_list`, else `rtnl_lock()` through v6.16, `lock_sock` from v6.17 | [mcast.c#L347-L354](https://github.com/torvalds/linux/blob/v6.6/net/ipv6/mcast.c#L347-L354) | [mcast.c#L347-L354](https://github.com/torvalds/linux/blob/v6.8/net/ipv6/mcast.c#L347-L354) | [mcast.c#L341-L348](https://github.com/torvalds/linux/blob/v7.2/net/ipv6/mcast.c#L341-L348); the change at [v6.17#L346](https://github.com/torvalds/linux/blob/v6.17/net/ipv6/mcast.c#L346) |
| `ipv6_sock_ac_close`: returns on an empty `ipv6_ac_list`, else `rtnl_lock()` through v6.16, a spinlock from v6.17 | [anycast.c#L213-L220](https://github.com/torvalds/linux/blob/v6.6/net/ipv6/anycast.c#L213-L220) | [anycast.c#L213-L220](https://github.com/torvalds/linux/blob/v6.8/net/ipv6/anycast.c#L213-L220) | [anycast.c#L232-L247](https://github.com/torvalds/linux/blob/v7.2/net/ipv6/anycast.c#L232-L247) |
| `packet_release` calls `packet_flush_mclist`: returns on an empty `mclist`, else `rtnl_lock()`; `struct packet_sock` is private to `net/packet/` | [af_packet.c#L3127-L3157](https://github.com/torvalds/linux/blob/v6.6/net/packet/af_packet.c#L3127-L3157), [#L3751-L3759](https://github.com/torvalds/linux/blob/v6.6/net/packet/af_packet.c#L3751-L3759) | [af_packet.c#L3121-L3151](https://github.com/torvalds/linux/blob/v6.8/net/packet/af_packet.c#L3121-L3151), [#L3745-L3753](https://github.com/torvalds/linux/blob/v6.8/net/packet/af_packet.c#L3745-L3753) | [af_packet.c#L3147](https://github.com/torvalds/linux/blob/v7.2/net/packet/af_packet.c#L3147), [#L3790-L3799](https://github.com/torvalds/linux/blob/v7.2/net/packet/af_packet.c#L3790-L3799) |
| `tcp_close` takes `lock_sock`, whose `might_sleep()` fires under a spinlock | [tcp.c#L2918-L2921](https://github.com/torvalds/linux/blob/v6.6/net/ipv4/tcp.c#L2918-L2921), [sock.c#L3502-L3507](https://github.com/torvalds/linux/blob/v6.6/net/core/sock.c#L3502-L3507) | [tcp.c#L2928-L2931](https://github.com/torvalds/linux/blob/v6.8/net/ipv4/tcp.c#L2928-L2931), [sock.c#L3520-L3525](https://github.com/torvalds/linux/blob/v6.8/net/core/sock.c#L3520-L3525) | [tcp.c#L3308](https://github.com/torvalds/linux/blob/v7.2/net/ipv4/tcp.c#L3308), [sock.c#L3824-L3829](https://github.com/torvalds/linux/blob/v7.2/net/core/sock.c#L3824-L3829) |

The fields the socket predicate reads are the ones these releases read: `inet_sk(sk)->mc_list`
(`include/net/inet_sock.h`), `inet6_sk(sk)->ipv6_mc_list` and `ipv6_ac_list`
(`include/linux/ipv6.h`), and `sk->sk_protocol`. `struct packet_sock` and `struct netlink_sock` are
not in a public header, which is why those two families are refused by family alone.

## The thread

| Fact | v6.6 and v6.8 | v7.2 |
|------|---------------|------|
| `kthread_stop` waits on the body's completion | [kthread.c#L696-L709](https://github.com/torvalds/linux/blob/v6.6/kernel/kthread.c#L696-L709), [v6.8](https://github.com/torvalds/linux/blob/v6.8/kernel/kthread.c#L696-L709) | [kthread.c#L747-L760](https://github.com/torvalds/linux/blob/v7.2/kernel/kthread.c#L747-L760) |
| a thread stopped before it ran returns `-EINTR` without calling the body | [kthread.c#L340-L384](https://github.com/torvalds/linux/blob/v6.6/kernel/kthread.c#L340-L384) | [kthread.c#L432](https://github.com/torvalds/linux/blob/v7.2/kernel/kthread.c#L432) |

## What does not take RTNL

`nf_unregister_net_hook` takes `nf_hook_mutex` and a grace period, and no RTNL:
[core.c#L488-L529 at v6.6](https://github.com/torvalds/linux/blob/v6.6/net/netfilter/core.c#L488-L529),
[v6.8](https://github.com/torvalds/linux/blob/v6.8/net/netfilter/core.c#L488-L529),
[v7.2#L481-L522](https://github.com/torvalds/linux/blob/v7.2/net/netfilter/core.c#L481-L522). `unregister_kprobe`,
`fsnotify_put_group`, `fsnotify_destroy_mark`, `hid_unregister_driver`, `cdev_del` and
`device_destroy` sleep on a mutex or a grace period of their own; none was traced to RTNL, and each
runs only at `lua_close`, since its class holds its runtime.

## The worker

| Fact | v6.6 | v6.8 | v7.2 |
|------|------|------|------|
| `queue_work_on` runs with interrupts saved, so a queue from a spinlock, softirq or hardirq is fine | [workqueue.c#L1825-L1831](https://github.com/torvalds/linux/blob/v6.6/kernel/workqueue.c#L1825-L1831) | [workqueue.c#L1828-L1834](https://github.com/torvalds/linux/blob/v6.8/kernel/workqueue.c#L1828-L1834) | [workqueue.c#L2442-L2448](https://github.com/torvalds/linux/blob/v7.2/kernel/workqueue.c#L2442-L2448) |
| `__flush_workqueue` waits for every item queued before it | [#L3131](https://github.com/torvalds/linux/blob/v6.6/kernel/workqueue.c#L3131) | [#L3134](https://github.com/torvalds/linux/blob/v6.8/kernel/workqueue.c#L3134) | [#L4067](https://github.com/torvalds/linux/blob/v7.2/kernel/workqueue.c#L4067) |
| `in_atomic()` cannot see a spinlock held on a non-preemptible kernel, and is not for driver code | [preempt.h#L180-L186 at v6.8](https://github.com/torvalds/linux/blob/v6.8/include/linux/preempt.h#L180-L186) | | |

Exports checked in `Module.symvers` for 6.8.0-138-generic: `queue_work_on`, `system_wq`,
`__flush_workqueue`, `kthread_stop`, `rtnl_is_locked` and `rtnl_trylock` are `EXPORT_SYMBOL`;
`alloc_workqueue`, `destroy_workqueue`, `flush_work`, `cancel_work_sync` and `system_unbound_wq`
are `EXPORT_SYMBOL_GPL`, which a `Dual MIT/GPL` module may use. `lockdep_rtnl_is_held` is exported
only with lockdep, and the host has none: `rtnl_is_locked` says whether anyone holds RTNL, never
whether the caller does, which is why the core keeps the task pointer #1045 added. `llist_add` and
`llist_del_all` are inline in `linux/llist.h` and lock-free.

