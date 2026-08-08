# Kernel notes: the AP control plane and the WPA authenticator

Verified reference for the kernel and reference-implementation facts the design
rests on. Line numbers are `net/wireless/nl80211.c` in the 6.8 HWE tree and
`src/...` in `hostap.git` (commit `39cd943`) unless noted. **Verify against the
kernel you build for** before writing code; nl80211 attributes and mac80211
control-port semantics move.

The two regimes this project spans:

* the **control plane** — creating the AP interface, beaconing, managing stations
  and keys, answering management frames — is generic netlink (`nl80211`), the same
  family `nl80211.wiphy`/`nl80211.interface` already use;
* the **authenticator** — the WPA 4-way handshake — is EAPOL frame I/O plus a
  per-station state machine and crypto. Its delivery path is the one unsettled
  piece; see "Open questions".

## 1. START_AP — verified requirements

`nl80211_start_ap` (`~5953`). The interface must already be `NL80211_IFTYPE_AP`
and administratively **up** (`NL80211_FLAG_NEED_NETDEV_UP` in the command's
`internal_flags`, `~16847`); otherwise the dispatch fails before the handler runs.

Required attributes — the handler returns `-EINVAL` without all three (`~5975`):

* `NL80211_ATTR_BEACON_INTERVAL` (u32)
* `NL80211_ATTR_DTIM_PERIOD` (u32)
* `NL80211_ATTR_BEACON_HEAD` (bytes)

Plus, in practice, `NL80211_ATTR_WIPHY_FREQ` (u32, the channel) parsed by
`nl80211_parse_chandef`, and optionally `NL80211_ATTR_SSID`, `NL80211_ATTR_BEACON_TAIL`.

**The beacon head is opaque at the netlink layer.** `nl80211_parse_beacon`
(`~5523`) only takes `nla_data`/`nla_len` and rejects a zero length; the 802.11
frame is validated deeper, in mac80211. So the binding passes head/tail as raw
bytes — the 802.11 frame construction is the caller's job, exactly as `hostapd`
builds `params->head`/`params->tail` and hands them through (`beacon.c:2263`;
driver at `driver_nl80211.c:5750`). The kernel/firmware inserts the TIM between
head and tail; the head ends before it. A minimal open-AP head that mac80211 and
hwsim accept — verified working in the `nl80211.ap` test — is: 802.11 mgmt header
(FC beacon, broadcast DA, BSSID as SA and addr3), timestamp/beacon-interval/
capability (ESS), then the SSID, Supported Rates, and DS Parameter Set elements.

`NL80211_CMD_STOP_AP` needs only the up AP interface.

## 2. Station and key commands

For phase 0. The command and attribute names below are verified present in the
6.8 uapi header (`uapi/linux/nl80211.h`); the exact required-attribute policy of
each handler is **not** yet verified the way START_AP's is (§1), and must be
confirmed in `net/wireless/nl80211.c` before writing the phase-0 code.

* `NL80211_CMD_NEW_STATION` / `DEL_STATION` / `SET_STATION` — add/remove/modify a
  station on the AP interface, keyed by `NL80211_ATTR_MAC`. Flags via
  `NL80211_ATTR_STA_FLAGS2` (a `nl80211_sta_flag_update` set/mask). The one that
  opens the controlled data path is `NL80211_STA_FLAG_AUTHORIZED`; `hostapd` sets
  it through `set_port_authorized` → `NL80211_STA_FLAG_AUTHORIZED`
  (`driver_nl80211.c:6232`). Association parameters: `STA_AID` (**u16** in the
  header — not the u32 `message.attrs` packs a number as; pack it explicitly),
  `STA_LISTEN_INTERVAL`, `STA_SUPPORTED_RATES`.
* `NL80211_CMD_NEW_KEY` / `DEL_KEY` — install a key on the interface (pairwise) or
  per-station (`NL80211_ATTR_MAC` present) with `NL80211_ATTR_KEY_DATA`,
  `KEY_IDX`, `KEY_CIPHER` (e.g. `WLAN_CIPHER_SUITE_CCMP` = `SUITE(0x000FAC, 4)` =
  `0x000fac04`, verified in `linux/ieee80211.h`), `KEY_SEQ`, `KEY_TYPE`.

These reuse the same genl-session `call` the existing `nl80211` objects use; the
target interface is `NL80211_ATTR_IFINDEX`.

## 3. The EAPOL control port

The 4-way handshake exchanges EAPOL-Key frames (EtherType `ETH_P_PAE` = `0x888E`).
The AP has two ways to carry them; `hostapd` implements both and prefers the
first on modern kernels.

### 3a. Control-port-over-nl80211 (the modern path)

Enabled at START_AP by setting `NL80211_ATTR_CONTROL_PORT_OVER_NL80211` (and
usually `NL80211_ATTR_SOCKET_OWNER`). Verified in `nl80211_start_ap`: on success,
`if (info->attrs[NL80211_ATTR_SOCKET_OWNER]) wdev->conn_owner_nlportid = info->snd_portid;`
— the kernel records the port id of the socket that sent START_AP.

* **RX.** A received EAPOL frame becomes an `NL80211_CMD_CONTROL_PORT_FRAME`
  message carrying `NL80211_ATTR_FRAME` (the raw frame), `NL80211_ATTR_MAC` (the
  source STA), `IFINDEX`, and `CONTROL_PORT_ETHERTYPE`, delivered by
  **`genlmsg_unicast(..., wdev->conn_owner_nlportid)`** (`__nl80211_rx_control_port`,
  `~19090`). That is: **unicast to the exact socket that started the AP**, not a
  multicast group. So the owning session receives EAPOL with an ordinary
  `receive()`.
* **TX.** Send `NL80211_CMD_CONTROL_PORT_FRAME` with the frame, dest MAC and
  ethertype (`nl80211_tx_control_port` on the hostapd side, `driver_nl80211.c:7054`).

The consequence for lunatik: the control-port EAPOL path reuses the `nl80211.ap`
session's socket. There is no new socket type and no multicast subscription. But
it places two concrete requirements the in-flight `nl80211.ap` does not yet meet —
neither a bug in it (its scope is start/stop), but both needed before this path
works:

* `ap:start` must **also** send `CONTROL_PORT_OVER_NL80211` and `SOCKET_OWNER`; the
  current call sends neither. This is an additive option on `ap:start` (e.g.
  `control_port = true`), not a breaking change.
* the START_AP socket must **stay open** to be the `conn_owner_nlportid` — the RX
  path returns `-ENOENT` when that port id is gone. The current `ap()` is
  transactional (open, `start`, close), so the authenticator cannot use a
  throwaway `ap():start(); ap():close()`; it holds a **long-lived** `ap` session
  and receives on it.

And it is, in any case, **one socket** — see the open question about per-CPU
delivery.

### 3b. AF_PACKET (the legacy path)

`hostapd`'s driver opens `socket(PF_PACKET, SOCK_DGRAM, htons(ETH_P_PAE))` bound to
the AP ifindex (`driver_nl80211.c:9595`; the generic `l2_packet_linux.c:271`) and
`sendto`/`recvfrom`s EAPOL directly. When control-port RX is available it does not
even open this socket. lunatik's `socket` already supports `AF_PACKET` (sockaddr_ll
with protocol+ifindex), so this path is reachable — and, unlike the single
control-port socket, `AF_PACKET` supports `PACKET_FANOUT` for per-CPU load
spreading. Whether the fanout hash gives useful per-STA distribution for L2 EAPOL
frames is unverified (see open questions).

## 4. The 4-way handshake (from hostapd, for phase 3)

The authenticator is `src/ap/wpa_auth.c`. It is a variable-driven Mealy machine:
boolean event variables (`EAPOLKeyReceived`, `MICVerified`, `TimeoutEvt`, …) drive
`SM_STEP(WPA_PTK)` (`wpa_auth.c:5547`) to a fixpoint (`wpa_sm_step`, guarded
against reentrancy by `in_step_loop`).

Pairwise state ladder and wire messages:

| State | Action | Advances on |
|-------|--------|-------------|
| `PTKSTART` | send msg 1/4 (ANonce, no MIC) | RX msg 2/4 → `PTKCALCNEGOTIATING`; timeout → resend, capped by `wpa_pairwise_update_count` (4) then `DISCONNECT` |
| `PTKCALCNEGOTIATING` | derive PTK from SNonce, verify msg-2 MIC | `MICVerified` |
| `PTKINITNEGOTIATING` | send msg 3/4 (GTK, MIC, key data AES-wrapped) | RX msg 4/4 (MIC ok) → `PTKINITDONE` |
| `PTKINITDONE` | install PTK, open controlled port | terminal until rekey/disconnect |

RX classifier `wpa_receive` (`wpa_auth.c:1700`) validates the replay counter and
(once `PTK_valid`) the MIC, copies SNonce on msg 2, sets the event variables, and
steps. Retransmit is a per-SM timer (`wpa_send_eapol`/`_timeout`, `~2366/2419`).

Crypto (all in `src/common/wpa_common.c` + `src/crypto/`), mapped to lunatik's
`crypto`:

* **PMK** (PSK): `PBKDF2-HMAC-SHA1(passphrase, ssid, 4096, 256)`. No PBKDF2 in
  `crypto`; compute it as iterated HMAC-SHA1 via `shash`. **[to verify: cost of
  4096 iterations in-kernel]**
* **PTK**: `wpa_pmk_to_ptk` → `sha1_prf` / `sha256_prf` / `sha384_prf` selected by
  AKM. Via `shash`.
* **EAPOL-Key MIC**: `hmac_sha1` (truncated, WPA2 default) / `omac1_aes_128`
  (AES-128-CMAC for SHA256 AKMs) / `hmac_sha256`/`_384`. `shash` covers HMAC;
  AES-CMAC needs checking in `crypto`. **[to verify: AES-CMAC availability]**
* **Key data encryption in msg 3**: NIST AES key wrap (`aes_wrap`/`aes_unwrap`).
  **[to verify: AES key wrap exposed via `crypto`/`skcipher`]**
* Nonces: kernel RNG (`crypto.rng` / `linux.random`).

The three `[to verify]` items are crypto-availability checks to do in phase 3
before committing to the handshake; each has a fallback (compute in Lua over a
lower primitive) but at a cost worth measuring.

## 5. Per-STA vs per-BSS state (the SMP split)

From `hostapd`'s structures (`src/ap/wpa_auth_i.h`), the split that decides the
sharded design:

| State | Scope | Parallelizable |
|-------|-------|----------------|
| 4-way FSM: ANonce/SNonce, PMK, **PTK**, `key_replay[]`, retransmit timer (`wpa_state_machine`) | **per-STA** | **yes — the shard unit**, per-STA serialization only |
| 802.1X port (`eapol_state_machine`) | per-STA | yes |
| station table / hash / AID bitmap | per-BSS | no — shared aggregate, atomic AID allocator |
| protection counters (non-ERP, …) | per-BSS | no — mutated on assoc, drives beacon |
| group keys GMK/**GTK**/IGTK, `GKeyDoneStations` (`wpa_group`) | per-BSS | no — single owner; GTK rekey is a cross-STA barrier |
| prebuilt RSN IE, PMKSA cache, stats | per-BSS | RCU reads; serialized writes / per-CPU counters |

The important asymmetry: **the handshakes parallelize, the shared aggregates do
not.** A sharded design gives the station table + AID allocator + group keys a
single owner (or concurrent structures) and lets the FSMs run on any CPU. In
lunatik terms, the per-STA state is an `rcu.table` entry keyed by MAC; the group
keys are owned by one runtime; GTK rekey is serialized.

## 6. The per-CPU infrastructure ([#676], [#678])

What the merged/in-flight foundation provides:

* `linux.numcpus()` → `nr_cpu_ids` (`lualinux.c`).
* `lunatik run <script> percpu` creates one runtime per CPU id, registered as
  `<script>:<cpu>` in `env.percpu`; the body runs once per runtime.
* The eBPF dispatch (`bpf_luaxdp_run`) resolves `<key>:<raw_smp_processor_id()>` —
  it runs on the runtime of the CPU the hook fired on.
* [#678]: `lunatik.cpu()` returns an instance's CPU id (nil for a plain runtime),
  and `netfilter.register` from a percpu instance is **affine at dispatch** — the
  hook acts only on packets processed on its CPU, `NF_ACCEPT`s the rest, so each
  packet is handled by exactly one instance with no locking. Global-registration
  constructors (`device`, `notifier`, `probe`, `hid`) refuse at load in a percpu
  instance.
* `spawn <script> percpu` ([#686], stacked on [#678]) starts one runtime **and one
  CPU-pinned kernel thread** per CPU id — process context, so it may sleep, with
  per-CPU state and no locking (the ksoftirqd shape, in Lua).

So there are two shapes for a per-CPU authenticator. A **spawned per-CPU worker**
([#686]): a CPU-pinned kthread that receives EAPOL in a bounded loop and runs the
whole handshake inline — it may sleep, so the keying (`NEW_KEY`/`SET_STATION`) and
the PBKDF2 happen in place. Or a **softirq per-CPU hook** (`netfilter`/XDP): fast
and affine at dispatch, but atomic, so the sleeping steps must be deferred to a
worker — two tiers. The worker shape is the cleaner one; what is still open is how
EAPOL reaches the right CPU's worker. That is the open question.

## Open questions

Documented as open, not resolved. Each is a phase-2 spike deliverable.

1. **Where EAPOL enters, and how it reaches a per-CPU worker.** With [#686]'s
   per-CPU workers (§6), the sleeping-context problem is solved; delivery is what
   is left. Candidates:
   * a per-CPU **`AF_PACKET`** socket (EtherType `0x888E`) on the AP netdev with
     `PACKET_FANOUT` — the kernel shards received EAPOL across the sockets, each
     worker reads its share and runs the handshake inline. The cleanest fit, **if**
     mac80211 exposes EAPOL to `AF_PACKET` on an AP netdev rather than consuming it
     into the control port first;
   * the **control port** (§3a) — one socket, unicast to the AP owner; fits a
     single worker, and going per-CPU needs a software MAC-hash dispatch;
   * a softirq **XDP/TC-BPF** hook via `bpf_luaxdp_run` — per-CPU by arrival, but
     atomic, so the keying and PBKDF2 defer to a worker (two tiers).

   The open, spike-answered part is **visibility**: does mac80211 let EAPOL reach
   `AF_PACKET`/a packet hook on an AP netdev, or does the control port take it
   first? If the control port is the only way in, the per-CPU story needs the
   software dispatch. **This gates the sharded design.**
2. **STA affinity, or shared state.** `PACKET_FANOUT_CPU` (and the XDP arrival CPU)
   shards by the CPU a frame lands on, not by station, so a station's frames may
   cross CPUs during its handshake — its state then must be shared (`rcu.table`,
   per-STA lock), not CPU-local. `PACKET_FANOUT_HASH` on the source MAC would give
   stable STA→CPU affinity and CPU-local state, **if** the hash keys on the L2
   source for a non-IP frame (unverified). This decides whether the per-STA state
   is shared or owned.
3. **Software MLME vs offload on hwsim.** Does hwsim require the AP to answer
   auth/assoc in software (`REGISTER_FRAME`/`FRAME`), or does it offload them?
   Phase 1 settles this; it changes where association policy is evaluated.
4. **Crypto availability** (the three `[to verify]` in §4): AES-CMAC, AES key wrap,
   and the cost of in-kernel PBKDF2. Phase 3, before the handshake.

## Version drift to watch

* nl80211 station/key attributes and `STA_FLAGS2` semantics; MLO adds
  `NL80211_ATTR_MLO_LINK_ID` to several commands (6.x).
* Control-port attributes (`CONTROL_PORT_OVER_NL80211`, `_NO_PREAUTH`,
  `_TX_STATUS`) are extended-feature-gated; check `NL80211_EXT_FEATURE_*`.
* `NL80211_ATTR_IFACE_SOCKET_OWNER` (auto-delete the interface when the owning
  socket closes) is a clean lifecycle idiom worth mirroring for the AP.

[#675]: https://github.com/luainkernel/lunatik/issues/675
[#676]: https://github.com/luainkernel/lunatik/pull/676
[#678]: https://github.com/luainkernel/lunatik/pull/678
[#686]: https://github.com/luainkernel/lunatik/pull/686

