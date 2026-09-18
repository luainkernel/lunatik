# Testing the kernel TLS binding

Lunatik's tests are shell scripts emitting KTAP, driving a kernel Lua script and asserting on `dmesg`
or on what userspace observes. `tests/socket/` is the closest existing model; read it and `tests/lib.sh`
(`run_test`, `mark_dmesg`, `dmesg_since`, `check_dmesg`, `ktap_skip`) first.

Run everything with `sudo lunatik test`, one suite with `sudo lunatik test tls`.

## What this suite needs that others do not

**Keying without a handshake.** The whole point of testing phases 1–3 is that they need no `tlshd` and
no real peer: install a known TLS session with **fixed key vectors** on both ends of a loopback socket
pair and exercise send/receive. This is exactly how the kernel's own kTLS selftest
(`tools/testing/selftests/net/tls.c`) works — both directions get the same key material, so plaintext
written on one end comes back decrypted on the other, with no negotiation. Use a published test vector
(or any fixed key) for AES-GCM-128 and ChaCha20-Poly1305.

**A skip gate for `tlshd`.** Whether the daemon runs decides what the upcall answers, so a case that
assumes no agent skips when one is installed or running, and a case that needs a completed handshake
skips when one is not. Each script reports `ktap_skip` per case it drops, so a green run shows skips
rather than a false pass. The development box does not have it.

**A config gate for `CONFIG_TLS`.** Skip cleanly if `tls.ko` is unavailable.

## Test matrix

Coverage means the matrix of operation × cipher × outcome, including the successes and the clean
failures, not a list of features.

### Phase 1: the ULP option

`tests/socket/setsockopt.sh` already covers the method itself, so this phase adds the option it
could not name.

| Test | Proves |
|------|--------|
| `tests/socket/ulp.sh` | `sk.tcp.ULP` resolves; `setsockopt(sol.TCP, tcp.ULP, "tls")` on a connected socket attaches the ULP; on an unconnected socket it raises `ENOTCONN` |

### Phase 2: keying

| Test | Proves |
|------|--------|
| `tests/tls/pack.sh` | `tls.pack` produces a blob of the exact size the kernel wants for each cipher; a part of the wrong length, or an unknown cipher, raises naming it |
| `tests/tls/key.sh` | attach ULP + install TLS 1.3 and TLS 1.2 AES-GCM-128 TX and RX with fixed vectors succeeds, and so does ChaCha20-Poly1305 (salt size 0); keying a socket with no ULP raises `ENOPROTOOPT`, a TLS 1.2 direction installed twice raises `EBUSY` while a TLS 1.3 one raises it below 6.14 and re-keys from it, and a wrong length, an unimplemented version, a second cipher on the other direction or ARIA-GCM outside TLS 1.2 each raise `EINVAL` |

### Phase 3: plaintext I/O

| Test | Proves |
|------|--------|
| `tests/socket/record.sh` | the two methods on a socket with no ULP: no record type reported, the control message ignored, the record type bounded to a byte, and `MSG_DONTWAIT` honoured. Needs no `CONFIG_TLS` |
| `tests/socket/scmrights.sh` | `receiverecord` on an `AF_UNIX` socket whose peer passes a descriptor carries no control buffer, so `scm_detach_fds` neither warns nor leaks the file: the peer passes the write end of a pipe and sees EOF on the other end. Needs no `CONFIG_TLS` |
| `loopback.sh` | with matching keys on both ends of a loopback pair, plaintext sent on A returns decrypted on B and reports `tls.record.DATA`; both directions, both versions, both available ciphers, and a record read in two calls |
| `record_type.sh` | a record sent with the alert type arrives as an alert, `tls.close_notify` emits what `tls_alert_send` does, the same alert read with plain `receive` raises `EIO`, and application data read that way still returns |
| `bounded_recv.sh` | a bounded `receiverecord` on an empty keyed socket returns promptly (`MSG_DONTWAIT`) or after its `SO_RCVTIMEO` (both measured), not blocking forever — the property a kthread relay depends on — and the session still carries plaintext afterwards |

`loopback.sh` and `record_type.sh` carry the phase: the first proves the data path works with no
userspace TLS at all, the second proves control records do not break reads. Sending the alert is the
stimulus the receive case needs, so `close_notify` is a case of `record_type.sh` and not a file of its
own, which would key the same session twice.

### Phase 4: handshake (no agent on the development box)

| Test | Proves |
|------|--------|
| `tests/handshake/upcall.sh` | the request reaches `handshake_req_submit` carrying the `struct file` the agent is handed: `ESRCH` rather than `EINVAL` says the file is there, a socket never connected raises `ENOTCONN`, and a second hello on the same socket answers `ESRCH` again with a clean kernel log |
| `tests/handshake/options.sh` | which hello the options pick, and what is refused before one is picked: a server hello with no credentials, more identities than `ta_my_peerids` holds, a `cert` with no `privkey`, an empty identity list the kernel's own psk arm refuses with `EINVAL`, and the option types and bounds that would otherwise reach the kernel truncated or as a zero |
| `tests/handshake/context.sh` | a runtime that may not sleep is refused at the call with `runtime context mismatch`, rather than left to deadlock on the completion |
| `tests/handshake/timeout.sh` | with a subscriber on the family's `tlshd` multicast group the submit succeeds, the wait runs out with `ETIMEDOUT`, the socket still closes, and closing the subscriber brings `ESRCH` back |
| `tests/handshake/socket_tls.sh` | `socket.tls.connect` is the three calls it composes: with no agent the hello is where it stops, so `ESRCH` says the `socket.new` and the `connect` before it ran and the socket reached the upcall connected and filed, where a name the module spells wrong raises a Lua error and never reaches an errno |

`upcall.sh`, `timeout.sh` and `socket_tls.sh` skip whole where `tlshd` is installed or running: an
agent would accept the request and change every outcome. A completed handshake, and the keyed socket
`socket.tls.connect` hands back, wait for a box carrying `ktls-utils`.

### Phase 5: the tunnel

| Test | Proves |
|------|--------|
| `tests/tunnel/plain.sh` | a spawned tunnel relays bytes between two plain sockets both ways; `stop` returns, measured; a second spawn rebinds the port and the name; a peer closing ends the relay; a softirq runtime is refused |
| `tests/tunnel/stall.sh` | a relay whose destination stopped reading is still stopped, holding a remainder it cannot deliver, and its body returns from the send that stop interrupted rather than propagating the `EINTR` the signal ends it with; it names which kernel makes the stop the bound's doing and which the signal's |
| `tests/tunnel/bounded.sh` | a direction stalled against a destination that stopped reading leaves the other one moving, which is what the send bound buys; the remainder a short send left pending is delivered once the far end drains and put through `opts.transform` only once; an option that is not positive, a send timeout or a receive size, is refused |
| `tests/tunnel/tls.sh` | a tunnel with a kTLS side relays plaintext in and re-encrypted out, reported as application data; a record of another type is dropped and the data behind it is not (fixed vectors, no `tlshd`) |
| `tests/tunnel/inspect.sh` | a plaintext transform is observed on the far end, applies to the direction its `from` picks, and drops the payload when it returns nothing |

`plain.sh` is the stoppability test and runs first: a tunnel that cannot be stopped is a hung
machine, so prove `stop` before adding TLS. `stall.sh` and `bounded.sh` run after it and before the
keyed cases, since they are the ones that would take the host down if the send were not bounded.

### Phase 6: examples

| Test | Proves |
|------|--------|
| `example_connect.sh` | the client example runs against a local TLS server (skips without `tlshd`) |
| `example_tunnel.sh` | the tunnel example forwards a request and stops cleanly (fixed-vector kTLS, no `tlshd`) |

## Conventions to follow

* skip, do not fail, when the kernel lacks `CONFIG_TLS`, or when whether `tlshd` runs decides the
  outcome instead of the code;
* mark `dmesg` before the run, read only what came after, and `check_dmesg` at the end;
* clean up sockets and stop threads in a `trap`, and run the cleanup once up front;
* `lunatik run` exits 0 even when the script fails to load — assert on output, never on exit status;
* one `.sh` per row, wired into its suite's `run.sh` and described in `tests/README.md`, same commit as
  the code it tests.

## A note on the loopback keying trick

The fixed-vector loopback pattern lets phases 1–3 and the TLS tunnel be tested with **no** `tlshd`, no
certificates, and no real peer — the same shortcut the kernel selftest uses. It exercises the record
layer and the whole Lua data path honestly; only a completed handshake genuinely needs the daemon,
and the upcall itself is covered by which refusal comes back. Keep the vectors in the test, not in
the library.

