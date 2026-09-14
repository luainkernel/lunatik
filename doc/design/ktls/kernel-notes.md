# Kernel notes: kernel TLS binding

Reference sheet for the `ktls` binding. Verified against Linux 6.8
(`/home/ubuntu/linux-hwe-6.8-6.8.0`, and the running kernel's `Module.symvers`), with version drift
noted. Re-check on the kernel you build for.

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

`tlshd` (from Oracle's `ktls-utils`) is **not installed** on the development box. The handshake path
(phase 4) therefore cannot be exercised here without installing it; the keying and plaintext paths
(phases 2–3) can, using fixed key vectors on a loopback pair.

## Keying — the two-step setsockopt path

1. `setsockopt(sk, SOL_TCP, TCP_ULP, "tls", 4)` → `tls_init` (`net/tls/tls_main.c:948`), which
   **requires `sk->sk_state == TCP_ESTABLISHED`** (`-ENOTCONN` otherwise): the socket must already be
   connected and handshaken. It attaches the `tls_context` and swaps `sk_prot`.
2. `setsockopt(sk, SOL_TLS, TLS_TX | TLS_RX, &crypto_info, len)` → `do_tls_setsockopt_conf`
   (`tls_main.c:612`). It copies the 4-byte header `struct tls_crypto_info { __u16 version;
   __u16 cipher_type; }`, looks up the cipher, requires `optlen` to equal that cipher's struct size
   exactly, and copies the rest. A second install on the same direction returns `-EBUSY`
   (`tls_main.c:637`).

`uapi/linux/tls.h`: option names `TLS_TX=1`, `TLS_RX=2`, `TLS_TX_ZEROCOPY_RO=3`,
`TLS_RX_EXPECT_NO_PAD=4`. Versions: TLS 1.2 `0x0303`, TLS 1.3 `0x0304`. Ciphers in 6.8: AES-GCM-128
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

kTLS is a TCP Upper Layer Protocol. `struct tcp_ulp_ops` (`include/net/tcp.h:2532`) has `init`,
`update`, `release`, `clone`, `get_info`, a `name[TCP_ULP_NAME_MAX]` (16), and `owner`; it does **not**
list `sendmsg`/`recvmsg`. A ULP intercepts the data path by having its `init` swap `sk->sk_prot` to a
`struct proto` with its own `sendmsg`/`recvmsg` — which is exactly what `tls` does
(`tcp_register_ulp(&tcp_tls_ulp_ops)`, `.name="tls"`, `tls_main.c:1123`; `update_sk_prot` at `:131`).
`tcp_register_ulp` / `tcp_unregister_ulp` are `EXPORT_SYMBOL_GPL`.

A socket carries **exactly one ULP**. This binding attaches the kernel's `tls` ULP and uses it; it
does not register a ULP of its own. Writing a *Lua* ULP (a `tcp_ulp_ops` whose `init` binds a Lunatik
runtime, so Lua becomes an upper-layer protocol for arbitrary L7) is a separate project — it is the
generalization the 2020 `net/tls` fork lacked and what Pedro Tammela's 2019 `ulp-lua` prototyped, but
it cannot share a socket with `tls`, so it does not compose into this one. Kept as a non goal in
`plan.md`.

## Plaintext I/O from a `struct socket *`

Once keyed, write plaintext with `kernel_sendmsg` (`net/socket.c:788`) and read decrypted data with
`kernel_recvmsg` (`:1088`); they land in `tls_sw_sendmsg` / `tls_sw_recvmsg`. Gotchas, all verified:

* **A control buffer is mandatory to see record types.** `tls_record_content_type` attaches a
  `TLS_GET_RECORD_TYPE` cmsg on the first record of a `recvmsg` (`tls_sw.c:1756`); if a non-DATA
  record arrives and the caller supplied no `msg_control`, the read fails `-EIO` (`tls_sw.c:1768`).
  `kernel_recvmsg` does not set up `msg_control`, so the plaintext read path needs a custom `recvmsg`
  carrying a control buffer. `tls_get_record_type` and `tls_alert_recv` (`net/handshake/alert.c`,
  both `EXPORT_SYMBOL`) decode the cmsg and the alert.
* **Setting a TX record type** (to emit a close_notify or other non-data record) uses a
  `TLS_SET_RECORD_TYPE` cmsg at `SOL_TLS`; `tls_process_cmsg` (`tls_main.c:238`) parses it, flushing
  any open record. Default is `TLS_RECORD_TYPE_DATA`.
* **kvec sends are always copied** — `tls_sw_sendmsg_locked` treats `is_kvec` specially
  (`tls_sw.c:1103`); kernel plaintext writes do not take the zerocopy/splice path. Fine, just not
  zero-copy.
* **RX waits on the strparser.** `tls_sw_recvmsg` blocks in `tls_rx_rec_wait` honoring
  `MSG_DONTWAIT`/`MSG_WAITALL` (`tls_sw.c:2015`); the wait does **not** check `kthread_should_stop`.
  So a relay loop must pass `MSG_DONTWAIT` or a receive timeout and poll `shouldstop()` — an unbounded
  read here is the classic unstoppable-kthread hazard.

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
  binding must attach a `struct file` to the socket before submitting.
* The submit contract is clean: 0 guarantees exactly one callback; a negative return guarantees no
  callback and the request is already freed — safe to build a state machine on.
* Mute `sk_data_ready` for the handshake and resume normal recv only after the callback
  (`tls-handshake.rst`), so nothing races `tlshd`.
* In-tree consumers submit then `wait_for_completion_interruptible_timeout` — in Lunatik this is a
  **sleepable** (`spawn`/process) runtime, never softirq.
* `tlshd` must run in the socket's network namespace; auth material (certs, PSKs) lives in kernel
  keyrings referenced by serial in the args.

## Version drift

| Feature | Landed | Note for 6.8 |
|---------|--------|--------------|
| TLS 1.3 | 5.1 | present |
| ChaCha20-Poly1305 | ~5.7 | present |
| handshake upcall (`net/handshake`, `tlshd`) | 6.4 / 6.5 | present |
| TLS 1.3 **KeyUpdate** / re-keying on RX | **6.14** | **absent in 6.8** — a long-lived 1.3 session that re-keys breaks; document and scope out |
| zerocopy `sendfile` for device offload TX | 6.11 | not needed here |

## Key file references

* keying / setsockopt: `net/tls/tls_main.c:948` (`tls_init`, ESTABLISHED), `:612`
  (`do_tls_setsockopt_conf`), `:238` (`tls_process_cmsg`)
* record type cmsg: `net/tls/tls_sw.c:1756` (`tls_record_content_type`), `:1768` (`-EIO` guard)
* SW paths: `tls_sw_sendmsg` `:1226`, `tls_sw_recvmsg` `:1954`
* ULP: `include/net/tcp.h:2532` (`tcp_ulp_ops`), `net/tls/tls_main.c:1123` (register)
* kernel socket I/O: `net/socket.c:788` (`kernel_sendmsg`), `:1088` (`kernel_recvmsg`)
* handshake upcall: `include/net/handshake.h`, `net/handshake/tlshd.c` (exports), `request.c:223`
  (`handshake_req_submit`), doc `Documentation/networking/tls-handshake.rst`
* alert/record readers: `net/handshake/alert.c` (`tls_get_record_type`, `tls_alert_recv`, exported)
* UAPI: `include/uapi/linux/tls.h`

