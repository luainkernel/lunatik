# Proposed Lua API: `ktls`

This is a design proposal, not a specification. Names and shapes are open for review; the kernel
constraints behind them (`kernel-notes.md`) are not. Phases 1 to 3 are in the tree, the
`linux.socket.tcp` and `linux.tls` namespaces, the `tls` module over the `socket:setsockopt`
`master` already had, and the record-type methods on the socket class; the rest is proposal.

Four pieces, low to high level:

* the `linux.socket.tcp` option namespace, over the `socket:setsockopt` `master` already has — a
  generic socket facility (phase 1);
* `linux.tls` — the kTLS constant namespaces, and `tls` — the `crypto_info` packer (phase 2);
* `handshake` — the kernel handshake upcall to `tlshd` (phase 4);
* `ktls` — high level helpers and the tunnel (phases 4–5), in Lua.

## Conventions

* Keys, IVs, salts and sequence numbers are binary strings; `tls.pack` assembles them into the exact
  `tls12_crypto_info_*` layout `setsockopt(SOL_TLS)` expects.
* Everything here is process-context: keying, handshake and the relay loop run in a `run` (process) or
  `spawn` runtime, never softirq. The kernel does the record crypto; Lua never touches a cipher.
* A kTLS socket is an ordinary Lunatik `socket` object once keyed; `send`/`receive` carry plaintext,
  and `sendrecord`/`receiverecord` carry plaintext plus the record type it travelled in.

## Phase 1 — the ULP option

    local sk = require("linux.socket")

    sock:setsockopt(sk.sol.TCP, sk.tcp.ULP, "tls")     -- attach the tls ULP
    sock:setsockopt(sk.sol.TLS, ltls.TX, crypto_info)  -- install keys (phase 2)

`sock:setsockopt(level, optname, optval)` is already on `master` and maps to the kernel `setsockopt`,
passing `optval` as a string payload (the kernel side uses `KERNEL_SOCKPTR`, so a Lua string becomes
the option buffer with no copy round trip through userspace). `sk.sol` carries `SOCKET`, `TCP`, `TLS`,
… and is emitted today; `sk.tcp`, which carries `ULP`, is what this phase adds. It is generic — not
TLS specific, and TLS is its first user.

## Phase 2 — `tls`: keying

    local tls = require("tls")

    local ltls = require("linux.tls")

    local info = tls.pack(tls.version.TLS_1_3, ltls.cipher.AES_GCM_128,
                          iv, key, salt, rec_seq)
    sock:setsockopt(sk.sol.TCP, sk.tcp.ULP, "tls")
    sock:setsockopt(sk.sol.TLS, ltls.TX, info)                 -- transmit direction
    sock:setsockopt(sk.sol.TLS, ltls.RX, info_rx)              -- receive direction

`tls.pack(version, cipher, iv, key, salt, rec_seq)` returns the packed `tls12_crypto_info_*` for the
chosen cipher, sized exactly as the kernel requires (a wrong length is rejected). The kernel
constants live where every other kernel constant does: `linux.tls` carries `TX` and `RX`,
`linux.tls.cipher` the cipher types and `linux.tls.size` their key material sizes, all from
`autogen`, which leaves `tls.version.{TLS_1_2, TLS_1_3}` on the module because the header composes
those two through a function-like macro autogen cannot read. A salt left out for ChaCha20 (salt size
0) is handled by the packer.

The socket must already be connected (the ULP attach requires `TCP_ESTABLISHED`); installing a
direction twice raises (`-EBUSY`), and keying a socket with no ULP on it raises `-ENOPROTOOPT`. Keys
come from somewhere — a userspace handshake (phase 4) or, for tests, fixed vectors.

## Phase 3 — plaintext I/O and control records

Once keyed, `sock:receive` returns decrypted plaintext and `sock:send` takes plaintext. Application
data needs nothing more; a control record needs a second pair of methods:

    local data, record = sock:receiverecord(n [, flags])   -- record is nil when none arrived
    local sent = sock:sendrecord(record, message)

`receiverecord` carries the `msg_control` buffer `receive` does not, so an alert or a handshake record
surfaces as the second return instead of failing the read with `-EIO`; the record type is the kernel's
own byte, named by `tls.record`. That buffer is not free: with `msg_control` set, an `AF_UNIX` read of
`SCM_RIGHTS` reaches a `WARN_ON_ONCE` in `scm_detach_fds` and leaks the files it was handed. So it
stays off `receive`, whose callers would also gain a return they did not ask for, and `receiverecord`
takes it only on `AF_INET` and `AF_INET6`, the families the ULP rides.

    sock:send(payload)                                     -- application data
    tls.close_notify(sock)                                 -- the close_notify alert record

`close_notify` is `sendrecord(tls.record.ALERT, "\1\0")`, in `tls` rather than on the socket class,
so TLS vocabulary stays out of the class every protocol shares. Receives are bounded
(`SO_RCVTIMEO_NEW`, or `linux.socket.msg.DONTWAIT`) so a relay loop in a kthread stays stoppable.

## Phase 4 — `handshake`: delegating to `tlshd`

    local handshake = require("handshake")

    -- process/spawn runtime only; blocks until tlshd answers
    local ok, peerid = handshake.client(sock, {
        peername = "example.com",            -- SNI
        timeout  = 5000,
        cert     = my_cert_serial,           -- optional x509 (keyring serials)
        privkey  = my_key_serial,
    })

`handshake.client(sock, opts)` fills `tls_handshake_args`, calls the exported `tls_client_hello_x509`
(or `_anon` / `_psk` by which options are present), and waits on a completion while `tlshd` performs
the handshake in userspace and installs the kTLS keys on the socket. On return the socket is keyed;
`sock:receive`/`sock:send` carry plaintext. `handshake.server(sock, opts)` mirrors it for the server
side. Requires `tlshd` running in the socket's network namespace.

The socket handed in must be connected and must have a `struct file` attached (the binding sets this
up). `sk_data_ready` is muted for the duration so nothing races `tlshd` on the byte stream.

## Phase 4 — `ktls`: the high level client

    local ktls = require("ktls")

    local sock = ktls.connect("93.184.216.34", 443, "example.com", 5000)
    sock:send("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
    print(sock:receive(4096))

`ktls.connect(ip, port, peername, timeout)` is `socket.new` → `connect` → attach ULP →
`handshake.client` → a keyed socket, in one call. Pure Lua over the pieces above.

## Phase 5 — the tunnel

The use case, in Lua. A spawned kthread relays plaintext between two sockets; one or both may be kTLS.

    local thread = require("thread")
    local linux  = require("linux")
    local tls    = require("tls")
    local sk     = require("linux.socket")

    local function relay(a, b, transform)
        local ok, data, record = pcall(a.receiverecord, a, 4096, sk.msg.DONTWAIT)
        if ok and record == tls.record.DATA then
            b:send(transform and transform(data) or data)
        end
    end

    return function()
        while not thread.shouldstop() do
            relay(client, upstream, inspect)     -- decrypted in, re-encrypted out
            relay(upstream, client)
            linux.schedule(10)
        end
    end

Both receives are bounded; the loop polls `shouldstop()`. `inspect` is where plaintext policy or
rewriting lives — the point of doing it in Lua. Which flows enter the tunnel can be decided by a
separate netfilter/XDP hook; the byte-moving loop stays here, in a sleepable kthread.

## Open questions for review

1. ~~Whether `receive` returns `(data, record)` or exposes the record type through a separate
   accessor.~~ Answered by phase 3: a separate `sock:receiverecord`, because a control buffer on
   `receive` changes what an `AF_UNIX` read does with `SCM_RIGHTS` and changes the arity of a call
   every existing script makes.
2. Whether `tls.pack` should take a table (`{version=, cipher=, iv=, key=, …}`) rather than positional
   arguments; positional is what it ships, a table reads better with many fields.
3. Whether `handshake.client`/`server` belong in their own `handshake` module or under `ktls`. They
   are usable without kTLS keying being visible, which argues for a separate module.
4. Whether the tunnel ships as a library helper (`ktls.tunnel(a, b, opts)` returning the thread body)
   or only as an example. A helper is convenient; an example keeps the loop visible and tweakable.

