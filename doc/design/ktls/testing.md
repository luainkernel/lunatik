# Testing the kernel TLS binding

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on `dmesg`
or on what userspace observes. `tests/socket/` is the closest existing model; read it and `tests/lib.sh`
(`run_test`, `mark_dmesg`, `dmesg_since`, `check_dmesg`, `ktap_skip`) first.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test ktls`.

## What this suite needs that others do not

**Keying without a handshake.** The whole point of testing phases 1–3 is that they need no `tlshd` and
no real peer: install a known TLS session with **fixed key vectors** on both ends of a loopback socket
pair and exercise send/receive. This is exactly how the kernel's own kTLS selftest
(`tools/testing/selftests/net/tls.c`) works — both directions get the same key material, so plaintext
written on one end comes back decrypted on the other, with no negotiation. Use a published test vector
(or any fixed key) for AES-GCM-128 and ChaCha20-Poly1305.

**A skip gate for `tlshd`.** The handshake path (phase 4) needs the `tlshd` daemon and auth material in
keyrings. The suite's `run.sh` checks for it once and reports `ktap_skip` per planned handshake test
when it is absent, so a green run on a box without `tlshd` shows skips rather than a false pass. The
development box does not have it.

**A config gate for `CONFIG_TLS`.** Skip cleanly if `tls.ko` is unavailable.

## Test matrix

Coverage means the matrix of operation × cipher × outcome, including the successes and the clean
failures, not a list of features.

### Phase 1: `setsockopt`

| Test | Proves |
|------|--------|
| `setsockopt.sh` | a socket option round-trips (set then, where readable, get); `socket.sol`/`socket.tcp` constants resolve; an unknown level/option raises rather than silently passing |
| `ulp.sh` | `setsockopt(TCP, ULP, "tls")` on a connected socket attaches the ULP; on an unconnected socket it raises `ENOTCONN` |

### Phase 2: keying

| Test | Proves |
|------|--------|
| `pack.sh` | `tls.pack` produces a blob of the exact size the kernel wants for each cipher; a wrong-length or unknown cipher raises |
| `key_gcm.sh` | attach ULP + install TLS 1.3 AES-GCM-128 TX and RX with fixed vectors succeeds |
| `key_chacha.sh` | same for ChaCha20-Poly1305 (salt size 0 handled) |
| `key_errors.sh` | installing before connect raises `ENOTCONN`; installing a direction twice raises `EBUSY` |

### Phase 3: plaintext I/O

| Test | Proves |
|------|--------|
| `loopback.sh` | with matching keys on both ends of a loopback pair, plaintext sent on A returns decrypted on B, both ciphers |
| `record_type.sh` | `receive` returns `"data"` for application data; a received close_notify surfaces as an `"alert"` record instead of `-EIO`; the alert decodes to close_notify |
| `close_notify.sh` | `sock:close_notify()` emits a control record the peer reads as an alert |
| `bounded_recv.sh` | a bounded `receive` on an empty socket returns promptly (timeout / would-block), not blocking forever — the property a kthread relay depends on |

`loopback.sh` and `record_type.sh` carry the phase: the first proves the data path works with no
userspace TLS at all, the second proves control records do not break reads.

### Phase 4: handshake (skips without `tlshd`)

| Test | Proves |
|------|--------|
| `handshake_anon.sh` | `handshake.client` on a connected socket to a local TLS server completes and yields a keyed socket (anon/encryption-only); skips if `tlshd` is absent |
| `handshake_timeout.sh` | a handshake to a non-responding peer times out cleanly and the socket is usable/closable, not wedged |
| `connect.sh` | `ktls.connect` performs connect + ULP + handshake and returns a socket that sends/receives plaintext against a local TLS echo server; skips without `tlshd` |

### Phase 5: the tunnel

| Test | Proves |
|------|--------|
| `tunnel_plain.sh` | a spawned tunnel relays bytes between two plain sockets; `stop` actually stops it (bounded recv + `shouldstop`), run twice with no leak |
| `tunnel_tls.sh` | a tunnel with a kTLS side relays plaintext in and re-encrypted out; the far end reads correct data (fixed vectors, no `tlshd`) |
| `tunnel_inspect.sh` | a plaintext transform in the relay is observed on the far end (proves the inspection point) |

`tunnel_plain.sh` is the stoppability test and must run first: a tunnel that cannot be stopped is a
hung machine, so prove `stop` before adding TLS.

### Phase 6: examples

| Test | Proves |
|------|--------|
| `example_connect.sh` | the client example runs against a local TLS server (skips without `tlshd`) |
| `example_tunnel.sh` | the tunnel example forwards a request and stops cleanly (fixed-vector kTLS, no `tlshd`) |

## Conventions to follow

* skip, do not fail, when the kernel lacks `CONFIG_TLS`, or when `tlshd` is absent;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* clean up sockets and stop threads in a `trap`, and run the cleanup once up front;
* `lunatik run` exits 0 even when the script fails to load — assert on output, never on exit status;
* one `.sh` per row, wired into `tests/ktls/run.sh` and described in `tests/README.md`, same commit as
  the code it tests.

## A note on the loopback keying trick

The fixed-vector loopback pattern lets phases 1–3 and the TLS tunnel be tested with **no** `tlshd`, no
certificates, and no real peer — the same shortcut the kernel selftest uses. It exercises the record
layer and the whole Lua data path honestly; only the handshake delegation genuinely needs the daemon,
and those tests skip when it is missing. Keep the vectors in the test, not in the library.

