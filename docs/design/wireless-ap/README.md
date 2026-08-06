# In-kernel wireless AP authenticator

Working documents for running the Access Point control plane and the WPA
authenticator (WPA2-PSK first) as Lua **inside the kernel**, over the `nl80211`
binding — part of what a userspace daemon (`hostapd`) does today, done as a
hot-loadable kernel script with a programmable association policy.

They exist so that a new contributor, with or without an AI coding assistant, can
pick the work up without first reverse engineering both `nl80211` and the 802.11
RSNA authenticator.

| Document | What it is for |
|----------|----------------|
| [plan.md](plan.md) | Current state, gap analysis, phases, non goals, risks, definition of done |
| [api.md](api.md) | Proposed Lua API: the `nl80211` control-plane objects and the `wpa` authenticator, with a worked example |
| [kernel-notes.md](kernel-notes.md) | Verified kernel reference: nl80211 control plane, the EAPOL control port, the 4-way handshake crypto, and the open questions |
| [testing.md](testing.md) | Test strategy on `mac80211_hwsim` with `wpa_supplicant` as the client, and the test matrix |

Start with `plan.md`. Read `kernel-notes.md` before writing any module, in
particular its "Open questions" section — the per-CPU delivery of EAPOL is not
settled, and one phase exists only to settle it.

## Working on this

The repository conventions that apply to every change here (build, test, style,
kernel context rules, commit discipline) are in [AGENTS.md](../../../AGENTS.md) at
the root of the repository. Read it once before the first patch. If you use an AI
assistant, point it at that file and at `kernel-notes.md`.

Three things decide whether this work goes well:

1. **This is a clean-room design, not a hostapd port.** `hostapd` is a
   single-process, single-threaded event loop — `grep pthread_create` on its
   source returns nothing, and its lock-free station tables are correct *only*
   because nothing runs concurrently. Its structure is the reference for the
   state machine and the crypto, not for the architecture. The kernel environment
   offers what a single-threaded daemon does not get for free: per-CPU execution
   for the per-station handshakes, and association policy evaluated in the packet
   path and reloadable live. Both have limits — see `plan.md`.

2. **The per-CPU foundation is a prerequisite, and one question inside it is
   open.** Per-CPU runtimes ([#676], merged) and per-CPU affinity at the
   registration points ([#678], resolving [#675]) are what make the SMP design
   possible; this project depends on them. What they do **not** yet answer is
   whether an EAPOL frame can be delivered to the per-CPU-affine runtime for the
   CPU it arrives on, or whether it only arrives out-of-band over the control
   port's single netlink socket. `kernel-notes.md` states both candidates
   honestly; a phase is dedicated to proving one before any handshake code is
   written.

3. **Bringing up an AP is bringing up a radio.** Test on `mac80211_hwsim` with a
   `wpa_supplicant` client, never on hardware whose network you care about — a
   rogue open AP on a real channel is antisocial at best. Everything here skips,
   not fails, when `mac80211_hwsim` is absent.

## Status

These documents describe the design; they do not track progress. What is merged,
what is in flight, and how far along each phase is lives on the project board.
Each phase is an issue there and lands as its own pull request.

The netlink and nl80211 groundwork this project builds on — the `socket`
`AF_NETLINK` support, the `netlink` namespace, the rtnetlink `rt` objects, generic
netlink, the softirq `channel`, and `nl80211.wiphy`/`nl80211.interface` — is
already on `master`. The AP bring-up itself (`nl80211.ap`, `rt.link:set`) is in
flight. Nothing of the authenticator exists yet.

[#675]: https://github.com/luainkernel/lunatik/issues/675
[#676]: https://github.com/luainkernel/lunatik/pull/676
[#678]: https://github.com/luainkernel/lunatik/pull/678

