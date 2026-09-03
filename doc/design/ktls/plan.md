# Plan: kernel TLS binding

Execution plan for the `ktls` binding. Built incrementally: each phase is a shippable pull request,
and the early phases rebase existing parked work rather than starting from zero.

## Expected results

1. A kernel Lua script can turn a connected kernel socket into a kTLS socket: attach the `"tls"` ULP
   and install a TLS session (version, cipher, iv, key, salt, sequence) with `setsockopt`.
2. Once keyed, a script reads decrypted plaintext and writes plaintext over the socket while the
   kernel does the record crypto transparently, with bounded receives safe for a kernel thread, and
   observes TLS control records (alert, close_notify) instead of erroring on them.
3. A script can request a TLS handshake on a connected socket through the kernel handshake upcall
   (`tls_client_hello_*` / `tls_server_hello_*`), delegating negotiation to `tlshd`, and get back a
   keyed socket — no in-kernel handshake, no forked `net/tls`.
4. Composing the above: a TLS tunnel written in Lua — a spawned kernel thread that splices decrypted
   plaintext between two sockets (one or both kTLS), the in-kernel TLS tunnel use case.
5. Examples plus a KTAP suite: a client `ktls.connect` example and a tunnel example, plus tests that
   key a loopback kTLS session with known vectors (no `tlshd` required) and exercise send, receive and
   alerts; the real-handshake test skips when the daemon is absent.

## Where we are today

kTLS is not reachable from Lua on `master`, but this is not a clean slate — there are two prior
efforts, and the gap between them is the whole story.

**The 2020 GSoC project** ([luainkernel/ktls](https://luainkernel.github.io/ktls/), Xinzhe Wang)
forked the kernel's `net/tls` out of tree and patched `tls_sw.c` to call Lua on decrypted plaintext in
`recvmsg`, with one `lua_State` per socket and a GnuTLS handshake in userspace. It reached the
interesting goal — Lua over decrypted L7 in the kernel — but by a route that does not survive: `net/tls`
has been reworked heavily since 5.4, a per-socket raw `lua_State` predates the whole modern runtime
model, and the report itself measured it slower than userspace Lua + kTLS. It is a design reference,
not a base.

**The parked `claude_tls` branch** (unmerged, based on `lunatik 4.2`, ~84 commits behind) is the
modern, in-tree-native approach that patches nothing:

* `lib/luasocket.c` adds `sock:setsockopt(level, optname, optval)` plus `socket.sol` / `socket.tcp`
  namespaces, including `TCP_ULP`. **This is the foundation, and it is not on `master`** —
  `master`'s `luasocket` has no `setsockopt` at all.
* `lib/luatls.c` provides `tls.pack(version, cipher, iv, key, salt, rec_seq)`, which builds the
  `tls12_crypto_info_*` binary blob for `setsockopt(SOL_TLS)`, plus the constants; AES-GCM-128/256 and
  ChaCha20-Poly1305, TLS 1.2/1.3, version-gated.
* `lib/luahandshake.c` binds the kernel handshake upcall (`tls_client_hello_x509` /
  `tls_server_hello_x509`), blocking on a completion while `tlshd` runs the handshake.
* `lib/ktls.lua` is a high level `ktls.connect(ip, port, peername, timeout)`.

What `claude_tls` does **not** have, and what this project adds, is the data path: it does client-side
session establishment and then plain `send`/`receive`, but no plaintext relay, no tunnel, and no
control-record handling. It also needs rebasing onto the current tree.

## What is missing

| Expected result | Gap |
|-----------------|-----|
| Key a socket for kTLS | `setsockopt` and the `tls.pack` packer exist only on the stale `claude_tls` branch, not `master`. |
| Plaintext I/O with control records | No binding reads decrypted data with a `msg_control` buffer, so TLS control records (alert, close_notify) would error `-EIO` rather than being surfaced. |
| Handshake upcall | The `luahandshake` binding exists on `claude_tls` but against an old base and without the socket+file plumbing spelled out. |
| The tunnel | Nothing splices plaintext between two sockets. |
| Tests and examples | The `claude_tls` tests cover connect; nothing covers keying with fixed vectors, alerts, or a tunnel. |

Supporting gaps:

* no `SOL_TLS` / `TLS_TX` / `TLS_RX` / `TCP_ULP` constants on `master`;
* the handshake upcall needs a connected `struct socket` **with a `struct file` attached**, which the
  socket binding must be able to provide;
* `tlshd` is not part of the repo's test environment, so the real-handshake path is not testable
  without installing `ktls-utils`.

## Shape of the work

New surface is small and mostly Lua, because kTLS is driven through socket options and the record
crypto is the kernel's. The C side is: the `setsockopt` binding (a generic socket facility, useful
beyond TLS), a `crypto_info` packer, and a handshake-upcall wrapper (socket+file setup plus a
sleepable wait around the exported `tls_*_hello_*` calls). Everything above that — keying, the relay
loop, policy on plaintext — is Lua.

The full API proposal is in `api.md`; the constraints are in `kernel-notes.md`. The one fact that
shapes the whole project:

> The Linux kernel implements the TLS **record** layer but not the TLS **handshake**. Every honest
> "in-kernel TLS" — nginx `SSL_sendfile`, HAProxy, Cilium's Envoy-based visibility, `tlshd` — keeps
> the handshake, certificate validation and policy in userspace and only kernelizes record crypto and
> byte movement. So a "TLS tunnel in Lua" is not a kernel TLS stack; it is a plaintext-splicing proxy
> over already-keyed kTLS sockets, with the handshake sourced from userspace. Design against that, or
> you end up forking `net/tls` like 2020 did.

The second shaping fact: kTLS is a TCP **ULP** (`tcp_register_ulp`, `.name = "tls"`), and a socket
carries exactly one ULP. We ride the existing `tls` ULP. Writing a *Lua* ULP — the generalization the
2020 fork should have used, and what Pedro Tammela's 2019 `ulp-lua` thesis prototyped — is a real and
appealing project, but it answers a different question (transparent interception of an application's
own socket) and cannot coexist with the `tls` ULP on one socket. It is a non goal here; see below.

## Phases

Each phase is one or more self-contained pull requests. The order is chosen so the first increment is
small, independently useful, and unblocks the rest.

### Phase 1: `setsockopt` on the socket (the foundation)

Rebase the `claude_tls` `sock:setsockopt(level, optname, optval)` plus the `socket.sol` / `socket.tcp`
constant namespaces onto the current tree. This is useful on its own (any socket option becomes
reachable, `TCP_ULP` included) and it is the prerequisite for everything else. Ship it as its own PR,
not folded into TLS.

Deliverables: the `setsockopt` method and the option-level namespaces in `lib/luasocket.c`, tests,
README and `config.ld` updates.

### Phase 2: key a socket for kTLS

The `tls` module: the `SOL_TLS` / `TLS_TX` / `TLS_RX` constants and `tls.pack(version, cipher, iv,
key, salt, rec_seq)` producing the `tls12_crypto_info_*` blob. Attach the ULP
(`sock:setsockopt(tcp.ULP, "tls")`) and install a session from Lua. Rebase `luatls.c`. Cover the
cipher/version matrix and the error cases (`-ENOTCONN` before connect, `-EBUSY` on a second install).

### Phase 3: plaintext I/O with control records

Read decrypted plaintext and write plaintext over the keyed socket, with bounded receives, and — the
new part — a `msg_control` buffer so a received alert or close_notify is surfaced (via
`tls_get_record_type` / `tls_alert_recv`) rather than turning into `-EIO`. Sending a non-data record
(a controlled close_notify) via the `TLS_SET_RECORD_TYPE` cmsg is included. This is the phase that
makes the socket usable as a data path, not just keyable.

### Phase 4: the handshake upcall

The `handshake` module binding `tls_client_hello_*` / `tls_server_hello_*`: build a connected socket
with a `struct file`, fill `tls_handshake_args`, submit, and wait on a completion in a sleepable
runtime while `tlshd` negotiates and keys the socket. Mute `sk_data_ready` for the duration. Rebase
`luahandshake.c` and `ktls.lua`; land the `ktls.connect` client example. Tests skip cleanly when
`tlshd` is not installed.

### Phase 5: the TLS tunnel

The use case: a spawned kernel thread that relays plaintext between two sockets — bounded `recv` on
side A, optional plaintext inspection or rewrite in Lua, `send` on side B (which re-encrypts if it is
a kTLS TX socket), symmetrically B to A, polling `thread.shouldstop()` each pass and yielding with
`linux.schedule()`. One or both sides may be kTLS. Steering (which flows enter the tunnel) can come
from a netfilter/XDP hook, but the relay stays in the kthread.

### Phase 6: examples and documentation

A client example and a tunnel example, a documentation pass, and the API cleanup the examples expose.
The tunnel example is honest about its limits (single buffer per read, no reassembly beyond what the
socket delivers), and documents the `tlshd` dependency and the TLS 1.3 KeyUpdate caveat.

## Sizing

Sized by what fits in a reviewable pull request.

| Scope | Phases |
|-------|--------|
| Minimum useful | 1 to 3. A socket can be keyed and used for plaintext I/O from Lua, tested with fixed vectors. |
| Complete | 1 to 6. Adds the delegated handshake, the tunnel, and the examples. |

Phase 3 is the boundary that matters: through it, kTLS is a usable data path in Lua with no userspace
dependency (keys installed directly). Phase 4 onward brings in `tlshd` for real handshakes.

## Non goals

* **A kernel TLS handshake.** The kernel has none by design; the handshake stays in userspace
  (`tlshd`, or an application). This binding never negotiates TLS itself.
* **A Lua ULP.** Writing a `tcp_ulp_ops` whose `init` binds a Lunatik runtime to the socket — letting
  Lua *be* an upper-layer protocol for arbitrary L7, the modern successor to Pedro Tammela's `ulp-lua`
  and the right framing the 2020 fork lacked — is a separate, worthwhile project. It serves transparent
  interception of an application's own socket, cannot share a socket with the `tls` ULP, and is more C
  and lower level. Its reusable ideas (ULP `init` to a runtime, a backlog-sized pool of pre-warmed
  runtimes, skb-as-`data`) are noted for that project, not built here.
* **A transparent `luatls` ULP** that both keys via kTLS and exposes plaintext to a Lua hook (the 2020
  dream done without a fork). Appealing, but it is the hard evolution on top of both this project and a
  Lua-ULP; not a first build.
* **Forking or patching `net/tls`.** The whole point of the modern approach is that it patches nothing.
* **Zero-copy sockmap/`sk_msg` datapath.** BPF socket-splice is a real optimization and a reference
  architecture, but it is C/BPF not Lua, carries live limitations (splice vs the psock queue, RCU),
  and is not needed for a first working tunnel. Deferred.

## Risks

| Risk | Mitigation |
|------|-----------|
| `claude_tls` is 84 commits stale; the socket changes may conflict | Rebase phase by phase, starting with `setsockopt` alone, not as one big drop. Re-verify against current `lib/luasocket.c`. |
| An unbounded `recv` in a kthread hangs the machine (the strparser does not check `kthread_should_stop`) | Every receive is bounded (`MSG_DONTWAIT` / `SO_RCVTIMEO_NEW`) and the loop polls `shouldstop()`; this is a hard rule, tested in phase 5. |
| Control records error `-EIO` without a `msg_control` buffer | Phase 3 makes the plaintext read path always carry a control buffer; tested with a close_notify. |
| Handshake upcall needs a `struct socket` with a `struct file` and a running `tlshd` | Phase 4 builds the file plumbing explicitly; tests skip when `tlshd` is absent, and the phase-3 path (manual keys) needs neither. |
| TLS 1.3 KeyUpdate is unsupported before kernel 6.14 | Documented; long-lived 1.3 sessions that re-key are out of scope on older kernels, and tests note it. |
| kTLS key/nonce reuse is not checked by the kernel | Documented as a caller responsibility; the packer does not invent sequence numbers. |

## Definition of done, per phase

1. builds clean on the target kernel, no new warnings;
2. LDoc on every new function and object type; new modules listed in `config.ld` in alphabetical order;
3. a row in the README module table;
4. a test in the right suite, wired into its `run.sh`, and described in `tests/README.md`;
5. the test skips (not fails) when the kernel lacks the config, or when `tlshd` is absent;
6. the full suite still passes: `sudo lunatik test`;
7. error paths audited: for every raise, whatever was acquired is released;
8. commits are small and each one stands alone; a rebased import is a distinct, reviewable commit.

