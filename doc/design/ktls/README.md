# Kernel TLS binding

Working documents for the `ktls` binding: a Lua interface to Linux kernel TLS, so kernel scripts can
key a connected socket for TLS, read and write plaintext while the kernel does the record-layer
crypto, delegate the handshake to the userspace `tlshd` daemon through the kernel handshake upcall,
and splice plaintext between sockets — enough to build a TLS proxy or an in-kernel TLS tunnel in Lua.

They exist so that a new contributor, with or without an AI coding assistant, can pick the work up
without first learning where kTLS ends and the TLS handshake begins.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | Current state (including the prior work), gap analysis, the incremental phases, non goals, risks, definition of done |
| [api.md](api.md) | Proposed Lua API: `socket:setsockopt`, the `tls` keying module, the `handshake` upcall module, `ktls` high level helpers, and the tunnel, with worked examples |
| [kernel-notes.md](kernel-notes.md) | Verified kernel reference: the two-step keying, exported symbols, the ULP framework and why we ride the `tls` ULP, plaintext I/O gotchas, version drift |
| [testing.md](testing.md) | Test strategy — keying a loopback session with known vectors (no `tlshd`), and skipping the real handshake when the daemon is absent |

Start with `plan.md`. Read `kernel-notes.md` before writing any C.

## Working on this

The repository conventions that apply to every change here (build, test, style, kernel context rules,
commit discipline) are in [AGENTS.md](../../../AGENTS.md) at the root of the repository. Read it once
before the first patch.

Three facts shape everything here, and are worth carrying from the start:

1. **The kernel does the TLS record layer, not the handshake.** There is no TLS handshake
   implementation in the kernel, by design. So this binding is not a kernel TLS stack; it keys
   sockets and moves plaintext, and the handshake comes from userspace (`tlshd`, or an application).
2. **This is incremental, and half the foundation already exists.** A parked `claude_tls` branch
   already has `socket:setsockopt`, a `tls` crypto-info packer, and a `handshake` upcall binding — but
   against an old base. The first increments rebase that onto the current tree; later increments add
   the plaintext data path and the tunnel. Each phase is a shippable pull request.
3. **kTLS is a TCP ULP.** We ride the kernel's existing `tls` upper-layer protocol; we do not write a
   Lua ULP. A generic "Lua is a ULP" binding is a worthwhile *separate* project (see the non goals in
   `plan.md`), not part of this one.

## Status

Tracked in the epic issue and the project board — the epic plus one issue per phase. Each phase lands
as its own pull request.

