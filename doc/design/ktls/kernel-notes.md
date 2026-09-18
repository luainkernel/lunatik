# Kernel notes: kernel TLS binding

Reference sheet for the `ktls` binding. Every line number below is read at tag **v6.12**, the series of
the development kernel, against the running kernel's `Module.symvers`, with version drift noted.
Re-check on the kernel you build for.

## The one fact that shapes everything

The kernel implements the TLS **record** subprotocol, not the **handshake**.
`Documentation/networking/tls-handshake.rst` states it: "there is no TLS handshake implementation in
the Linux kernel." kTLS does symmetric record crypto once keys are installed; negotiating those keys
(ClientHello/ServerHello, cert exchange, validation) happens in userspace — an application's TLS
library, or the `tlshd` daemon reached through the handshake upcall. Design against this; do not try
to make the kernel negotiate TLS.

## Config and environment

| Config | For | Running kernel |
|--------|-----|----------------|
| `CONFIG_TLS` (`tls.ko`) | kTLS itself | `=m`, module present |
| `CONFIG_TLS_DEVICE` | NIC offload (not required) | `=y` |
| `CONFIG_NET_HANDSHAKE` | the handshake upcall | `=y`, built in |
| `CONFIG_CRYPTO_GCM`, `CONFIG_CRYPTO_CCM` | the AES sessions | `=m` |
| `CONFIG_CRYPTO_CHACHA20POLY1305` | the ChaCha20-Poly1305 session | `=m` |
| `CONFIG_CRYPTO_SM4_GENERIC`, `CONFIG_CRYPTO_ARIA` | the SM4 and ARIA sessions | **not set** |

The AEAD is allocated when the keys are installed, so the last row is a limit on what can be tested
here: `linux.tls.cipher` names SM4 and ARIA, and installing one of those sessions on this box fails
at `crypto_alloc_aead`.

`tlshd` (from Oracle's `ktls-utils`) is **not installed** on the development box. A completed
handshake therefore cannot be exercised here; what can, and is, is the submit path and which refusal
comes back (phase 4). The keying and plaintext paths (phases 2–3) need no agent at all, using fixed
key vectors on a loopback pair.

## Keying — the two-step setsockopt path

1. `setsockopt(sk, SOL_TCP, TCP_ULP, "tls", 4)` → `tls_init` (`net/tls/tls_main.c:945`), which
   **requires `sk->sk_state == TCP_ESTABLISHED`** (`-ENOTCONN` otherwise, `:963`): the socket must
   already be connected and handshaken. It attaches the `tls_context` and swaps `sk_prot`.
2. `setsockopt(sk, SOL_TLS, TLS_TX | TLS_RX, &crypto_info, len)` → `do_tls_setsockopt_conf`
   (`tls_main.c:612`), which refuses in this order: an `optlen` below the 4-byte header
   `struct tls_crypto_info { __u16 version; __u16 cipher_type; }` with `-EINVAL` (`:623`); a
   direction already keyed with `-EBUSY` (`:638`), which from 6.14 refuses only a version other than
   TLS 1.3 and re-keys a 1.3 direction whose new blob repeats its version and cipher (v6.14
   `tls_main.c:643`, `-EINVAL` when either differs); whatever `validate_crypto_info` refuses (`:646`,
   below); a cipher outside `TLS_CIPHER_MIN..MAX`, for which `get_cipher_desc` returns NULL, with
   `-EINVAL` (`:651`); and an `optlen` that is not that cipher's struct size exactly, again `-EINVAL`
   (`:656`). What follows the header is then copied flat (`:661`), so the payload is the header and
   then `iv`, `key`, `salt`, `rec_seq`, with no per-field placement.

`validate_crypto_info` (`tls_main.c:587`) adds three refusals, all `-EINVAL`: a version that is
neither `TLS_1_2_VERSION` nor `TLS_1_3_VERSION` (`:590`); ARIA-GCM under anything but TLS 1.2
(`:594`); and, once the other direction carries a session, a version or cipher that differs from it
(`:603`). Judging the version is the kernel's, which is why the packer does not.

**Keying a socket that carries no `tls` ULP raises `-ENOPROTOOPT`, not `-ENOTCONN`.** `SOL_TLS` is
not `SOL_TCP`, so `tcp_setsockopt` (`net/ipv4/tcp.c:4027`) hands it to `ip_setsockopt`, which refuses
every level but `SOL_IP` (`net/ipv4/ip_sockglue.c:1414`). `-ENOTCONN` belongs to the ULP attach
alone. On a socket that does carry the ULP, an option name other than the four at `SOL_TLS` is
`-ENOPROTOOPT` as well, from `do_tls_setsockopt`'s default arm (`:793`).

`uapi/linux/tls.h`: option names `TLS_TX=1`, `TLS_RX=2`, `TLS_TX_ZEROCOPY_RO=3`,
`TLS_RX_EXPECT_NO_PAD=4`. Versions: TLS 1.2 `0x0303`, TLS 1.3 `0x0304`. Ciphers in 6.12: AES-GCM-128
(51), AES-GCM-256 (52), AES-CCM-128 (53), CHACHA20-POLY1305 (54, salt 0 / IV 12), SM4-GCM (55),
SM4-CCM (56), ARIA-GCM-128 (57), ARIA-GCM-256 (58). Each cipher's `tls12_crypto_info_*` carries
`iv`, `key`, `salt`, `rec_seq` after the common header — this is what `tls.pack` assembles.

### No in-kernel setup API, but a module can drive setsockopt directly

There is **no exported** `tls_set_sw_offload`, `tcp_set_ulp`, or `do_tls_setsockopt`; they are static
or module-internal. But the setsockopt handlers take `sockptr_t` and `copy_from_sockptr` accepts
kernel pointers, and the entry points `sock_common_setsockopt` / `tcp_setsockopt` are exported. So a
module holding a `struct socket *sock` does:

    sock->ops->setsockopt(sock, SOL_TCP, TCP_ULP, KERNEL_SOCKPTR("tls"), 4);
    sock->ops->setsockopt(sock, SOL_TLS, TLS_TX, KERNEL_SOCKPTR(&info), sizeof(info));

This is the same mechanism `net/mptcp/sockopt.c` and `net/smc` use for `TCP_ULP`. It is not a blessed
kTLS API, but it is structurally supported and is exactly what `tlshd` does over the fd. This is what
`socket:setsockopt` wraps.

## The ULP framework, and why we ride the `tls` ULP

kTLS is a TCP Upper Layer Protocol. `struct tcp_ulp_ops` (`include/net/tcp.h:2559`) has `init`,
`update`, `release`, `clone`, `get_info`, a `name[TCP_ULP_NAME_MAX]` (16), and `owner`; it does **not**
list `sendmsg`/`recvmsg`. A ULP intercepts the data path by having its `init` swap `sk->sk_prot` to a
`struct proto` with its own `sendmsg`/`recvmsg` — which is exactly what `tls` does
(`tcp_register_ulp(&tcp_tls_ulp_ops)` at `tls_main.c:1145`, the ops at `:1120` with `.name="tls"`;
`update_sk_prot` at `:131`).
`tcp_register_ulp` / `tcp_unregister_ulp` are `EXPORT_SYMBOL_GPL`.

A socket carries **exactly one ULP**. This binding attaches the kernel's `tls` ULP and uses it; it
does not register a ULP of its own. Writing a *Lua* ULP (a `tcp_ulp_ops` whose `init` binds a Lunatik
runtime, so Lua becomes an upper-layer protocol for arbitrary L7) is a separate project — it is the
generalization the 2020 `net/tls` fork lacked and what Pedro Tammela's 2019 `ulp-lua` prototyped, but
it cannot share a socket with `tls`, so it does not compose into this one. Kept as a non goal in
`plan.md`.

## Plaintext I/O from a `struct socket *`

Once keyed, write plaintext with `kernel_sendmsg` (`net/socket.c:787`) and read decrypted data with
`kernel_recvmsg` (`:1093`); they land in `tls_sw_sendmsg` / `tls_sw_recvmsg`. Gotchas, all verified:

* **A control buffer is mandatory to see record types.** `tls_record_content_type` attaches a
  `TLS_GET_RECORD_TYPE` cmsg on the first record of a `recvmsg` (`tls_sw.c:1752`); if a non-DATA
  record arrives and the caller supplied no `msg_control`, the read fails `-EIO` (`tls_sw.c:1766`).
  `kernel_recvmsg` (`:1093`) sets `msg_control_is_user` and the iterator and touches neither
  `msg_control` nor `msg_controllen`, so the caller fills them on the `struct msghdr` it already
  builds — no custom `recvmsg`. `net/sunrpc/xprtsock.c:389`'s `xs_sock_recv_cmsg` is the sibling to
  copy: a stack `union { struct cmsghdr cmsg; u8 buf[CMSG_SPACE(sizeof(u8))]; }`, and
  `msg_controllen != sizeof(u)` afterwards as the "a cmsg arrived" test, since `put_cmsg`
  (`net/core/scm.c:231`) advances `msg_control` and shortens `msg_controllen` by `CMSG_SPACE(len)`.
  The header is therefore read at the base that was handed in, never at `msg_control` after the call.
* **The decoding helpers are out of reach.** `tls_get_record_type` and `tls_alert_recv` are declared
  in `include/net/handshake.h:45-46` and exported plainly, but `net/handshake/alert.c` and
  `include/net/tls_prot.h` both arrived in **6.6** and are built only under `CONFIG_NET_HANDSHAKE`.
  Linking them would raise this binding's floor from 6.0 for three lines of `cmsg_level`/`cmsg_type`
  comparison and two bytes the script already holds, so the binding does both itself, and
  `net/tls_prot.h`'s `TLS_RECORD_TYPE_*` names cannot come from `autogen` either: they are a table in
  `lib/tls.lua`, keyed as a spec over that header would key them.
* **Setting a TX record type** (to emit a close_notify or other non-data record) uses a
  `TLS_SET_RECORD_TYPE` cmsg at `SOL_TLS`; `tls_process_cmsg` (`tls_main.c:238`) parses it, flushing
  any open record. Default is `TLS_RECORD_TYPE_DATA`. The kernel's own emitter is `tls_alert_send`
  (`net/handshake/alert.c`), which is the one alert symbol that is **not** in `Module.symvers` while
  its siblings are, so a binding builds that cmsg rather than calling it.
* **A control buffer on a generic receive is not free**, which is why the record-type read is a
  method of its own and not an extension of `socket:receive`. With `msg_control` non-NULL,
  `__scm_recv_common` (`include/net/scm.h:172`) stops taking its early exit and reaches
  `scm_detach_fds`, whose first statement is `if (WARN_ON_ONCE(!msg->msg_control_is_user)) return;`
  (`net/core/scm.c:330`) — and `kernel_recvmsg` sets `msg_control_is_user = false`. That return is
  before `__scm_destroy` (`:368`), so an `AF_UNIX` socket receiving `SCM_RIGHTS` goes from "fds
  dropped, `MSG_CTRUNC` set" to a kernel `WARNING:` and every file of the message leaked.
  The same branch also writes an `SCM_CREDENTIALS` cmsg under `SOCK_PASSCRED`.
* **A `SOL_TLS` cmsg on a socket with no ULP is ignored, not refused.** `tcp_sendmsg_locked` passes a
  non-empty control buffer to `sock_cmsg_send` (`net/core/sock.c:2947`), which walks it and
  `continue`s on every level but `SOL_SOCKET`, so the payload goes out as ordinary bytes.
* **kvec sends are always copied** — `tls_sw_sendmsg_locked` treats `is_kvec` specially
  (`tls_sw.c:1103`); kernel plaintext writes do not take the zerocopy/splice path. Fine, just not
  zero-copy.
* **RX waits on the strparser.** `tls_sw_recvmsg` blocks in `tls_rx_rec_wait` honoring
  `MSG_DONTWAIT`/`MSG_WAITALL` (`tls_sw.c:1308`, called at `:2009`); the wait itself tests neither
  `kthread_should_stop` nor a bound of its own.
  So a relay loop must pass `MSG_DONTWAIT` or a receive timeout and poll `shouldstop()` — an unbounded
  read here is the classic unstoppable-kthread hazard.
* **TX has no per-call bound at all.** `tls_sw_sendmsg` and `tcp_sendmsg` wait for room in
  `sk_stream_wait_memory` (`net/core/stream.c:118`), which reads `sk_sndtimeo`, and the
  `struct msghdr` `kernel_sendmsg` builds carries no `MSG_DONTWAIT`. `SO_SNDTIMEO` is therefore
  the only bound a caller that does not build its own `msghdr` can put on a send.
* **`kthread_stop` became a signal in 6.1.** It sets `TIF_NOTIFY_SIGNAL` on the task
  (`kernel/kthread.c:707` at v6.1, absent at v5.15), which `signal_pending` reads, so the
  `signal_pending` arm of `sk_stream_wait_memory` (`net/core/stream.c:137`) and of `tls_rx_rec_wait`
  (`tls_sw.c:1355`) ends the wait with `-EINTR` and whatever was copied — the errno itself where
  nothing had been copied yet, `do_error` returning a count only `if (copied + copied_syn)`
  (`net/ipv4/tcp.c:1333` at v6.12), so a send a stop finds waiting on a destination that never reads
  answers the stop as an error. Below 6.1 there is no such flag, and `wait_woken`
  (`kernel/sched/wait.c:452` at v5.15) returns its timeout unchanged once
  `kthread_should_stop` is set, so `sk_wait_event` (`include/net/sock.h:1091` at v5.15) writes back
  the same `current_timeo`, the `!*timeo_p` exit at `net/core/stream.c:135` is never reached, and the
  loop spins. `SO_SNDTIMEO` ends that wait no more than the missing signal does, so below 6.1 a relay
  stopped while a send to a destination that never reads is waiting is not joined there. What the
  bounds buy on every kernel is a pass that ends: one direction stalled does not hold the other, and
  `shouldstop` is polled. Measured on 6.12: a send blocked against a stalled peer with a 10 s
  `SO_SNDTIMEO` returned 2048 bytes the moment the thread was stopped, which is the signal arriving
  and not the bound elapsing.

## The handshake upcall — module-facing and exported

`net/handshake` (Linux **6.4**; first consumers NFS/SunRPC and NVMe-TCP in **6.5**). Include
`<net/handshake.h>`. A consumer fills:

    struct tls_handshake_args {
        struct socket  *ta_sock;        /* connected, MUST have ta_sock->file */
        tls_done_func_t ta_done;        /* completion callback */
        void           *ta_data;        /* cookie */
        const char     *ta_peername;    /* SNI, optional */
        unsigned int    ta_timeout_ms;
        key_serial_t    ta_keyring, ta_my_cert, ta_my_privkey;
        unsigned int    ta_num_peerids;
        key_serial_t    ta_my_peerids[5];
    };

and calls one of (all `EXPORT_SYMBOL`, plain — not GPL — present in this kernel's `Module.symvers`):
`tls_client_hello_x509`, `tls_client_hello_psk`, `tls_client_hello_anon`, `tls_server_hello_x509`,
`tls_server_hello_psk`, plus `tls_handshake_cancel(sk)` and `tls_handshake_close(sock)`. Each wraps
`handshake_req_submit`, which multicasts a netlink event that `tlshd` consumes; `tlshd` runs the
handshake, promotes the socket to the `tls` ULP, installs keys via `SOL_TLS`, and returns it. The
callback `tls_done_func_t(void *data, int status, key_serial_t peerid)` fires once, from netlink
(process) context; `status` 0 means the session is up.

Hard constraints:

* `handshake_req_submit` returns `-EINVAL` without `sock->file` (`net/handshake/request.c:230`): the
  binding must attach a `struct file` to the socket before submitting, and the agent is handed that
  same file (`fd_install(fd, get_file(sock->file))`, `netlink.c:125`). Past that test, a host with no
  agent answers `-ESRCH` from `genl_has_listeners` (`netlink.c:47`), so which of the two comes back
  says whether the file was attached.
* **The file is permanent.** `sock_alloc_file` (`net/socket.c:461`) stores it in `sock->file` and
  **releases the socket itself on failure** (`:471`), so a failed attach leaves a dangling private to
  clear; and `__sock_release` returns without `iput` while `sock->file` is set (`:669`), leaving the
  socket for the file's own put. A socket that took a file is released with `fput(sock->file)`, never
  `sock_release` — `drivers/nvme/host/tcp.c:1390` is the precedent. `fput` defers through
  `task_work_add` or the `delayed_fput` workqueue (`fs/file_table.c:480`), so it is safe from any
  context.
* The submit contract is clean: 0 guarantees exactly one callback; a negative return guarantees no
  callback and the request is already freed — safe to build a state machine on.
* **A pending request holds the `sk`, not the socket.** `handshake_req_submit` ends with
  `sock_hold(req->hr_sk)` (`request.c:272`) and nothing more, while `handshake_nl_accept_doit` takes
  the socket back out of it — `sock = req->hr_sk->sk_socket` then
  `fd_install(fd, get_file(sock->file))` (`netlink.c:112`, `:125`) — with no check between them. A
  close meanwhile runs `__sock_release` → `inet_release` → `tcp_close`, whose `sock_orphan`
  (`net/ipv4/tcp.c:3137`) NULLs `sk->sk_socket`. A consumer whose socket another thread can close
  therefore holds the file reference for the whole request, not for the submit alone.
* `tls_handshake_cancel` answers false when `handshake_complete` already won
  `HANDSHAKE_F_REQ_COMPLETED` (`request.c:313`), which still owes exactly one callback. A caller whose
  completion lives on its own stack waits that callback out rather than returning on the false. The
  cancel never destroys the request, so it stays keyed on the socket in `handshake_rhashtbl` until
  `handshake_sk_destruct` (`:86`) runs, and the next submit answers `-EBUSY` (`:257`): a retry after a
  timeout needs a socket of its own.
* The callback's `status` reaches the consumer through `tls_handshake_done`'s `-status`
  (`tlshd.c:107`), so the agent's own errno arrives negative while
  `handshake_nl_accept_doit`'s internal `handshake_complete(req, -EIO, NULL)` (`netlink.c:131`) comes
  back out positive. `-abs(status)` covers both.
* `tls_client_hello_psk` refuses `ta_num_peerids` outside 1..5 with `-EINVAL` before it allocates
  (`tlshd.c:340`); `tls_server_hello_psk` takes `ta_my_peerids[0]` and checks nothing.
* `ta_peername` is stored by pointer (`tlshd.c:53`) and read when the agent accepts (`:222`), after
  the submitting call has returned, so the caller keeps the string alive.
* **The ULP is the agent's to attach.** `Documentation/networking/tls-handshake.rst:37` — `tlshd`
  promotes the socket and installs the keys itself, and neither in-tree consumer mentions `TCP_ULP` at
  v6.12. A ULP already on the socket makes the agent's own attach `-EEXIST`.
* **`sk_data_ready` is not the consumer's to mute.** The documentation asks a consumer to suppress its
  own receive path, and that is what the consumers do: `xs_data_ready`
  (`net/sunrpc/xprtsock.c:1449`) calls the protocol default first and only then skips queueing its own
  worker, and NVMe-TCP installs `nvme_tcp_data_ready` only after `nvme_tcp_start_tls` returns
  (`drivers/nvme/host/tcp.c:1862`, reached from `nvme_tcp_start_queue`, against the handshake at
  `:1790`). Lunatik installs none, and a no-op one would stop
  waking `tlshd`'s own blocking reads on the file it was handed.
* In-tree consumers submit then `wait_for_completion_interruptible_timeout` — in Lunatik this is a
  **sleepable** (`spawn`/process) runtime, never softirq.
* `tlshd` must run in the socket's network namespace; auth material (certs, PSKs) lives in kernel
  keyrings referenced by serial in the args.

## Version drift

| Feature | Landed | Note for 6.12 |
|---------|--------|---------------|
| TLS 1.3 | 5.1 | present |
| ChaCha20-Poly1305 | ~5.7 | present |
| ARIA-GCM-128/256 (`TLS_CIPHER_ARIA_GCM_*`) | 6.1 | present; the only constant here younger than the 6.0 floor |
| `kthread_stop` raising `TIF_NOTIFY_SIGNAL` | 6.1 | present; below it only the bounds end a socket wait in a kthread |
| handshake upcall (`net/handshake`, `tlshd`) | 6.4 / 6.5 | present |
| alert helpers (`net/handshake/alert.c`, `net/tls_prot.h`) | 6.6 | present; above the 6.0 floor, so not linked |
| TLS 1.3 **KeyUpdate** / re-keying on RX | **6.14** | **absent in 6.12** — a long-lived 1.3 session that re-keys breaks; document and scope out |
| zerocopy `sendfile` for device offload TX | 6.11 | not needed here |

## Key file references

* keying / setsockopt: `net/tls/tls_main.c:945` (`tls_init`, ESTABLISHED), `:587`
  (`validate_crypto_info`), `:612` (`do_tls_setsockopt_conf`), `:238` (`tls_process_cmsg`)
* record type cmsg: `net/tls/tls_sw.c:1752` (`tls_record_content_type`), `:1766` (`-EIO` guard)
* SW paths: `tls_sw_sendmsg` `:1226`, `tls_sw_recvmsg` `:1950`
* ULP: `include/net/tcp.h:2559` (`tcp_ulp_ops`), `net/tls/tls_main.c:1120` (ops), `:1145` (register)
* kernel socket I/O: `net/socket.c:787` (`kernel_sendmsg`), `:1093` (`kernel_recvmsg`), `:2301`
  (`do_sock_setsockopt`, exported at `:2340`)
* stopping a kthread out of a socket wait: `net/core/stream.c:118` (`sk_stream_wait_memory`), `:137`
  (its `signal_pending` arm), `kernel/kthread.c:699` (`kthread_stop`), `kernel/sched/wait.c:413`
  (`wait_woken`)
* handshake upcall: `include/net/handshake.h`, `net/handshake/tlshd.c` (exports), `request.c:223`
  (`handshake_req_submit`), `:286` (`handshake_complete`), `:313` (`handshake_req_cancel`),
  `net/handshake/netlink.c:47` (`genl_has_listeners`), `:125` (`fd_install`), doc
  `Documentation/networking/tls-handshake.rst`
* the socket's file: `net/socket.c:461` (`sock_alloc_file`), `:649` (`__sock_release`),
  `fs/file_table.c:480` (`fput`)
* alert/record readers: `net/handshake/alert.c` (`tls_get_record_type`, `tls_alert_recv`, exported;
  `tls_alert_send`, not exported), `include/net/tls_prot.h` (the `TLS_RECORD_TYPE_*` and `TLS_ALERT_*`
  names)
* ancillary data: `net/core/scm.c:231` (`put_cmsg`), `:320` (`scm_detach_fds`),
  `net/sunrpc/xprtsock.c:389` (`xs_sock_recv_cmsg`), `net/core/sock.c:2947` (`sock_cmsg_send`)
* UAPI: `include/uapi/linux/tls.h`

