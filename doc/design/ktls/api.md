# Proposed Lua API: `ktls`

This is a design proposal, not a specification. Names and shapes are open for review; the kernel
constraints behind them (`kernel-notes.md`) are not. Some of this exists already on the parked
`claude_tls` branch and is rebased in; the rest is new.

Four pieces, low to high level:

* `socket:setsockopt` plus `socket.sol` / `socket.tcp` option namespaces — a generic socket facility
  (phase 1);
* `tls` — kTLS constants and the `crypto_info` packer (phase 2);
* `handshake` — the kernel handshake upcall to `tlshd` (phase 4);
* `ktls` — high level helpers and the tunnel (phases 4–5), in Lua.

## Conventions

* Keys, IVs, salts and sequence numbers are binary strings; `tls.pack` assembles them into the exact
  `tls12_crypto_info_*` layout `setsockopt(SOL_TLS)` expects.
* Everything here is process-context: keying, handshake and the relay loop run in a `run` (process) or
  `spawn` runtime, never softirq. The kernel does the record crypto; Lua never touches a cipher.
* A kTLS socket is an ordinary Lunatik `socket` object once keyed; `send`/`receive` carry plaintext.

## Phase 1 — `socket:setsockopt`

    local socket = require("socket")

    sock:setsockopt(socket.sol.TCP, socket.tcp.ULP, "tls")     -- attach the tls ULP
    sock:setsockopt(socket.sol.TLS, tls.TX, crypto_info)       -- install keys (phase 2)

`sock:setsockopt(level, optname, optval)` maps to the kernel `setsockopt`, passing `optval` as a
string payload (the kernel side uses `KERNEL_SOCKPTR`, so a Lua string becomes the option buffer with
no copy round trip through userspace). `socket.sol` carries `SOCKET`, `TCP`, `TLS`, …; `socket.tcp`
carries `ULP` and the rest. This is generic — it is not TLS specific, and TLS is its first user.

## Phase 2 — `tls`: keying

    local tls = require("tls")

    local info = tls.pack(tls.version.TLS_1_3, tls.cipher.AES_GCM_128,
                          iv, key, salt, rec_seq)
    sock:setsockopt(socket.sol.TCP, socket.tcp.ULP, "tls")
    sock:setsockopt(socket.sol.TLS, tls.TX, info)              -- transmit direction
    sock:setsockopt(socket.sol.TLS, tls.RX, info_rx)           -- receive direction

`tls.pack(version, cipher, iv, key, salt, rec_seq)` returns the packed `tls12_crypto_info_*` for the
chosen cipher, sized exactly as the kernel requires (a wrong length is rejected). Constants:
`tls.version.{TLS_1_2, TLS_1_3}`, `tls.cipher.{AES_GCM_128, AES_GCM_256, CHACHA20_POLY1305, …}`,
`tls.{TX, RX}`. Missing salt for ChaCha20 (salt size 0) is handled by the packer.

The socket must already be connected (the ULP attach requires `TCP_ESTABLISHED`); installing a
direction twice raises (`-EBUSY`). Keys come from somewhere — a userspace handshake (phase 4) or, for
tests, fixed vectors.

## Phase 3 — plaintext I/O and control records

Once keyed, `sock:receive` returns decrypted plaintext and `sock:send` takes plaintext. Two additions
this phase makes real:

    local data, record = sock:receive(n)     -- record defaults to "data"

`receive` carries a `msg_control` buffer so a non-application record surfaces as a second return
(`"alert"`, `"handshake"`, …) instead of failing the read with `-EIO`. A returned alert can be
inspected (level, description) so a close_notify is a clean end of stream rather than an error.

    sock:send(payload)                       -- application data
    sock:close_notify()                      -- send a close_notify alert record

`close_notify` sends a control record via the `TLS_SET_RECORD_TYPE` cmsg. Receives are bounded
(`sock:timeout(ms)` or a non-blocking flag) so a relay loop in a kthread stays stoppable.

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

    local function relay(a, b, transform)
        local data, record = a:receive(4096)
        if data and record == "data" then
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

1. Whether `receive` returns `(data, record)` (proposed) or exposes the record type through a separate
   accessor. The two-return form reads well and matches how a caller must branch on control records.
2. Whether `tls.pack` should take a table (`{version=, cipher=, iv=, key=, …}`) rather than positional
   arguments; positional mirrors the existing `claude_tls` shape, a table reads better with many fields.
3. Whether `handshake.client`/`server` belong in their own `handshake` module or under `ktls`. They
   are usable without kTLS keying being visible, which argues for a separate module.
4. Whether the tunnel ships as a library helper (`ktls.tunnel(a, b, opts)` returning the thread body)
   or only as an example. A helper is convenient; an example keeps the loop visible and tweakable.

