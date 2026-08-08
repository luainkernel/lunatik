# Plan: in-kernel wireless AP authenticator

Execution plan for running the 802.11 Access Point control plane and the WPA
authenticator as a Lua kernel script, over the `nl80211` binding. The long-term
target is a hot-loadable, policy-programmable AP authenticator that uses two
things the kernel environment offers and a userspace daemon has to build for
itself: per-CPU execution for the per-station handshakes, and policy evaluated in
the packet path.

## Where we are today

The netlink groundwork is done and merged. On `master`:

* `socket` speaks `AF_NETLINK`, and the `netlink` namespace groups request/response
  sessions (`netlink.rt`, `netlink.genl`) and the softirq-safe `netlink.channel`;
* `netlink.rt` exposes rtnetlink as per-object classes: `route`, `link`, `addr`,
  `rule`, each `add`/`del`/`list` over a `NETLINK_ROUTE` session;
* `netlink.nl80211` is a genl subclass bound to the `"nl80211"` family, with
  `wiphy():list()` (radios) and `interface():add/del/list` (create/destroy a
  virtual interface in a given mode);
* per-CPU runtimes exist ([#676]): a `percpu` script gets one runtime per CPU id,
  and the eBPF dispatch resolves to the runtime of the CPU a hook runs on;
* `crypto` provides `shash` (HMAC-SHA1/256/384), `skcipher`, `aead`, `rng`, `hkdf`
  — the primitives the 4-way handshake needs.

In flight (open pull requests, prerequisites for this project):

* `nl80211.ap():start/stop` — begin/stop beaconing with a raw beacon head;
* `rt.link():set{up}` — bring an interface administratively up over `RTM_SETLINK`;
* per-CPU **affinity** at the registration points ([#678], resolving [#675]):
  `lunatik.cpu()` exposes an instance's CPU id, and `netfilter.register` from a
  percpu instance only acts on packets processed on that instance's CPU.

So "we can bring up an open AP from the kernel" is nearly true. What does not exist
at all is the authenticator: no station management, no key installation, no EAPOL,
no 4-way handshake, no policy.

## What is missing

| Outcome | Gap |
|---------|-----|
| Manage associated stations | No `station` object. No add/del/set/list, no per-STA flags, no `AUTHORIZED` port control. |
| Install keys | No `key` object. No `NEW_KEY`/`DEL_KEY`, no PTK/GTK installation. |
| Receive and send EAPOL | Never done. EAPOL delivery to an in-kernel script is unproven — see "The open question" below. |
| Run the 4-way handshake | No authenticator. No per-STA state machine, no PMK/PTK derivation, no MIC, no key wrap, no replay protection, no GTK rekey. |
| Programmable association policy | The point of the project; nothing yet. |

Supporting gaps: the nl80211 `station`/`key`/`AKM`/cipher/auth-type constants are
not in the autogen allowlist; there is no representation for an 802.11 element
(IE) in Lua beyond hand-packing bytes; and the WPA crypto (PRF, AES key wrap,
AES-CMAC MIC) has not been exercised through the `crypto` module.

## The idea that shapes the design

Two facts, one merged and one from reading `hostapd`, set the architecture.

**hostapd runs its authenticator on one thread.** It is a single event loop
(`src/utils/eloop.c`, one process-global `struct eloop_data`, no threads), so
every station's 4-way handshake — nonce generation, `PBKDF2`, the `PRF`, AES key
wrap — is serviced on that one loop, on one CPU. This is not an oversight to
optimize away: its lock-free station tables and non-reentrant state machines are
correct *because* nothing runs concurrently, so using more than one CPU would
mean rearchitecting that core, not setting a flag. The consequence is that when
many stations authenticate at once, their crypto serializes on a single core.

**The per-station handshake is independent.** From `hostapd`'s own structures, the
`wpa_state_machine` (per-STA: ANonce/SNonce, PMK, PTK, replay counters, retransmit
timer) shares nothing on the write side with another station's, except reads of
the group key and the PSK. The per-BSS shared state is small and identifiable: the
group keys (`wpa_group`: GMK/GTK/IGTK, and the GTK rekey fan-out), the station
table and AID allocator, the protection counters, and the prebuilt RSN IE. See
`kernel-notes.md` §"Per-STA vs per-BSS state" for the full split.

So the design aims at a **per-CPU authenticator**: with [#686], a `spawn ... percpu`
worker is a CPU-pinned kernel thread per CPU — process context, so it may sleep,
which the handshake's keying and PBKDF2 need — each handling the handshakes for the
stations whose frames land on its CPU. This is subject to "The open question"
below, which decides whether EAPOL can reach a per-CPU worker at all. The
per-station handshake state lives in a shared `rcu.table` (read-mostly, keyed by
STA MAC), because per-CPU delivery shards by the CPU a frame *arrives on*, not by
station: a station's frames are not guaranteed to land on one CPU, so its state
cannot be CPU-local unless the delivery is made STA-affine (see the open questions).
The parallelism is real (N CPUs deriving PTKs concurrently), but it is shared-state
parallelism, not share-nothing. The per-BSS group-key subsystem has a single owner
and RCU readers; GTK rekey is the one inherently cross-CPU operation (a barrier
over all stations).

The authenticator's only outward dependencies are the four `hostapd` uses:
`send_eapol`, `set_key`, `get_psk`, `set_port_authorized`. Those map to the
control port (or packet path), the `key` object, a Lua policy callback, and the
`station` object's `AUTHORIZED` flag. That small seam is the module boundary.

### The open question

**Can an EAPOL frame reach the per-CPU-affine runtime for the CPU it arrives on?**
The merged affinity ([#678]) is for the packet path — a `netfilter`/XDP hook fires
on the CPU processing the packet. But an AP receives EAPOL over the 802.11
**control port**, which the modern kernel delivers as an `NL80211_CMD_CONTROL_PORT_FRAME`
event, **unicast to the single socket that started the AP** (`conn_owner_nlportid`)
— not through the packet path, and not per-CPU. The two ways out:

* **A — packet-path delivery.** Catch EAPOL (EtherType `0x888E`) with a per-CPU
  `netfilter`/XDP/TC hook on the AP netdev, so [#678]'s affinity applies directly.
  Open: whether mac80211 exposes control-port frames to that hook at all, and
  whether frame steering gives useful per-CPU distribution.
* **B — control-port delivery + software dispatch.** Receive over the one
  control-port socket and route each frame to a per-CPU runtime by hashing the STA
  MAC. Gives stable STA→CPU affinity (CPU-local state becomes possible) but the
  dispatcher does not exist and the single socket is a serialization point at
  ingress.

This is not settled and must not be pretended settled. Phase 2 exists only to
answer it with a prototype. Until it is answered, the handshake phases assume the
model that does not depend on it: a shared per-STA `rcu.table` reachable from any
runtime, with per-STA serialization.

## Phases

Each phase is one or more self-contained pull requests, sized to what fits in one
reviewable diff. The order keeps the project useful at every cut: an open AP that
accepts clients (end of phase 2) is already a demonstrable result, and every later
phase is additive.

### Phase 0: finish the control plane

`nl80211.station():add/del/set/list` and `nl80211.key():add/del`. The station
object carries the AID, capabilities and flags; `set{authorized=true}` opens the
controlled port (`NL80211_STA_FLAG_AUTHORIZED`). The key object installs a PTK or
GTK (`NEW_KEY` with cipher/key-index/key-data). Add the `station`/`key`/AKM/cipher
constants to the autogen allowlist. Validate against `mac80211_hwsim`: add a
station, set it authorized, install a key, see it in a dump.

Depends on `nl80211.ap` and `rt.link:set` landing first.

### Phase 1: associate an open client

Register for management frames (`REGISTER_FRAME`), receive auth/assoc requests,
and answer them (`FRAME` TX) — the software-MLME path. Add the station on assoc,
open its port. Milestone: a `wpa_supplicant` client associates to the open AP and
`iw dev` shows it. This is the first time something a user can see works, and it is
the whole of "open AP" — no crypto yet.

Whether hwsim/mac80211 requires software MLME or offloads auth/assoc is settled
here with a prototype, not an assumption.

### Phase 2: the EAPOL I/O spike (the gate)

Prove, on hwsim with a real `wpa_supplicant` client, that the kernel script can
**receive and send** an EAPOL-Key frame. The question the spike settles is where
EAPOL enters and how it reaches a per-CPU worker (`kernel-notes.md` "Open
questions" 1). The leading candidate, now that [#686] gives per-CPU sleepable
workers, is a per-CPU `AF_PACKET` socket (`0x888E`) with `PACKET_FANOUT` feeding a
`spawn ... percpu` worker that handles the handshake inline — clean if mac80211
exposes EAPOL to `AF_PACKET` on an AP netdev rather than taking it into the control
port first. The control-port socket (one owner) and a softirq XDP/TC hook (atomic,
two-tier) are the fallbacks. No handshake logic, no PR of a public API until RX and
TX are demonstrated; the phase produces a throwaway prototype and a findings note.

If neither path works cleanly, that is a finding too: it caps the project at "open
AP + external authenticator" and is worth knowing before writing crypto.

### Phase 3: one 4-way handshake, single runtime

The WPA2-PSK authenticator for a single station, in one runtime (no percpu yet):
the `WPA_PTK` state machine (msg 1–4), PMK from the passphrase (`PBKDF2` via
`shash`), PTK via the `PRF`, the msg-2/4 MIC, AES key wrap of the GTK in msg 3,
replay counters, retransmit timeout. Install the PTK/GTK via phase 0's `key`, open
the port. Milestone: `wpa_supplicant` completes WPA2-PSK against the kernel AP and
passes encrypted traffic on hwsim.

### Phase 4: shard across CPUs

Move the authenticator to a `spawn ... percpu` worker ([#686]) — a CPU-pinned
kernel thread per CPU — with per-STA state in a shared `rcu.table`, using the
phase-2 delivery path. The per-BSS group-key subsystem gets a single owner. Prove
correctness under concurrent associations (many clients at once) and measure the
speedup against phase 3's single runtime. GTK rekey stays serialized (the
cross-CPU barrier).

### Phase 5: programmable policy and the demo

The user-facing payoff: an association-policy callback (accept / reject /
per-client parameters / band-steer) that is plain Lua, hot-reloadable, evaluated in
the association path with no userspace round trip. Plus an `examples/` AP and a
documentation pass. WPA3-SAE and enterprise (EAP/RADIUS) are explicitly out of the
initial scope; see non goals.

## Non goals

Stated so they do not creep in:

* **WPA3-SAE and enterprise (EAP/RADIUS/TLS).** The initial target is WPA2-PSK and
  open. SAE adds a dragonfly handshake in management frames; enterprise adds an
  EAP state machine and a RADIUS client. Both are natural sequels and both are out
  of scope until WPA2-PSK works end to end.
* **Multi-BSS / multiple radios in one script.** One BSS on one radio. The per-BSS
  shared state is designed as if there could be more, but managing several is a
  later concern.
* **Replacing the whole of hostapd.** No config-file compatibility, no ACL/MAC
  filtering beyond what the policy callback expresses, no WPS, no 802.11r/k/v.
* **Beacon/IE construction as a library.** Phase-1 builds the minimal beacon by
  hand (as `nl80211.ap` already does in its test). A general 802.11 element
  builder is a possible follow-up, not a dependency.

## Risks

| Risk | Mitigation |
|------|-----------|
| EAPOL cannot be delivered per-CPU (the open question) | Phase 2 is a gate: prove RX/TX before any handshake code. A negative result caps scope but is found early. |
| Shared per-STA `rcu.table` becomes a contention or correctness problem under load | Phase 4 measures it against phase 3; per-STA serialization keeps cross-STA contention out. Only optimize (STA→CPU affinity, path B) if the numbers demand it. |
| GTK rekey (cross-CPU fan-out over all stations) races the per-CPU handshakes | Single-owner group-key subsystem; rekey is a serialized barrier, not sharded. Designed in from phase 4, not retrofitted. |
| nl80211/mac80211 version drift (attributes, control-port semantics, MLO link ids) | Verify every command against the target kernel's `uapi/linux/nl80211.h` and `net/wireless/nl80211.c` before writing it, as `kernel-notes.md` does. |
| Software MLME vs offload differs between hwsim and real drivers | Phase 1 prototypes the auth/assoc path on hwsim; the design notes where a real driver would diverge. |
| WPA crypto details (PRF selection by AKM, key-wrap IV, MIC truncation) are easy to get subtly wrong | `kernel-notes.md` pins each primitive to its `hostapd` reference; the phase-3 test is a real `wpa_supplicant`, which rejects a wrong MIC. |

## Definition of done, per phase

A phase is done when all of the following hold. This is the review checklist.

1. builds clean on the target kernel, no new warnings;
2. LDoc on every new function and object type; the module in `config.ld` in
   alphabetical order and a row in the README module table;
3. a test in the right suite, wired into its `run.sh`, described in
   `tests/README.md`, that **skips** (not fails) without `mac80211_hwsim`;
4. coverage is the matrix of operation by outcome, the success paths included, not
   only the error paths;
5. the full suite still passes: `sudo lunatik test`;
6. error paths audited: for every raise, whatever was acquired is released;
7. commits are small and each one stands alone;
8. any design question the phase was meant to answer is answered in the docs with a
   result, not left implied.

[#675]: https://github.com/luainkernel/lunatik/issues/675
[#676]: https://github.com/luainkernel/lunatik/pull/676
[#678]: https://github.com/luainkernel/lunatik/pull/678
[#686]: https://github.com/luainkernel/lunatik/pull/686

