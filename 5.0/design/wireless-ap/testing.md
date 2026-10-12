# Testing the AP authenticator

The whole stack is testable without hardware on `mac80211_hwsim`, driving a real
`wpa_supplicant` client against the kernel AP. Every test **skips** (not fails)
when `mac80211_hwsim` or `wpa_supplicant` is absent, mirroring the existing
`nl80211`/`nl80211_iface` tests.

## What the harness already gives, and what is missing

The `nl80211` and `nl80211_iface` tests establish the pattern: `modprobe
mac80211_hwsim radios=2`, resolve the wiphy by dumping (indices are not `0`/`1`),
create/keep an AP interface, assert via a dump, clean up in a `trap`. Reuse it.

Missing, to build as the phases need it:

* **a client.** The authenticator tests need a station that actually associates and
  runs the handshake. `wpa_supplicant` on the *second* hwsim radio is the client:
  a scratch config (`network={ ssid=... psk=... }` or `key_mgmt=NONE` for open),
  `wpa_supplicant -i wlanN -c scratch.conf`, then poll `wpa_cli status` for
  `wpa_state=COMPLETED`. Skip if `wpa_supplicant` is not installed.
* **a clean radio between tests.** Manual `iw`/`ip` fiddling leaves interfaces in
  the wrong mode and wedges later runs (a documented gotcha — see AGENTS.md). Each
  `.sh` does its own `modprobe`/`rmmod` and creates the AP through lunatik, not by
  hand; the formal `.sh` is the authoritative validation, never a manual scratch.

## Test matrix

Per phase, the operation-by-outcome matrix (successes included, not only errors).

### `tests/nl80211/` (phase 0, extends the existing suite)

* **station_adddel** — `station:add` a fake STA on an AP interface, see it in a
  dump with its AID; `set{authorized=true}`, confirm the flag; a second add of the
  same MAC raises; `del`, confirm gone.
* **key_adddel** — `key:add` a pairwise key for a station and a group key, confirm
  no error; `del`; adding with a bad cipher raises.

### `tests/wireless/` (new suite, phases 1–4)

* **associate** (phase 1) — bring up an open AP; a `wpa_supplicant` client on the
  second radio reaches `COMPLETED`; the STA appears in `station:list` and `iw dev`
  shows it associated. The negative: a policy that rejects the MAC keeps it out.
* **eapol_spike** (phase 2) — not a public-API test but a gate: the chosen
  delivery path receives an EAPOL frame the client sent and the script can send one
  back. Asserts the raw RX/TX, from `dmesg` markers, before any handshake exists.
* **wpa2_psk** (phase 3) — a `wpa_supplicant` client with the right PSK reaches
  `COMPLETED` **and passes encrypted traffic** (a ping over the associated link);
  a client with the wrong PSK fails the 4-way (MIC rejected) and does not
  associate. This is the real end-to-end check — `wpa_supplicant` verifies the
  MIC, so a wrong handshake does not pass.
* **wpa2_psk_percpu** (phase 4) — several clients associate concurrently and all
  reach `COMPLETED`; per-CPU instance counters show the handshakes actually ran on
  more than one CPU (the same shape as the [#678] affinity test, where per-instance
  counters must sum to the packet count, not N times it); a correctness check that
  the shared per-STA `rcu.table` served concurrent associations without loss.

### `tests/wireless/` (phase 5)

* **policy** — the association callback is hot-reloaded between two client
  attempts (rejected, then admitted) with no AP restart, proving live policy.

## Conventions to follow

Per AGENTS.md and the existing tests:

* skip, do not fail, without `mac80211_hwsim` / `wpa_supplicant`;
* `mark_dmesg` before `run_script`, `check_dmesg` after; assert on the kernel
  script's `print`s via `dmesg`, since `lunatik run` exits 0 on a script error;
* clean up in a `trap` (kill `wpa_supplicant`, delete the AP interface, `rmmod
  hwsim`) and run the cleanup once up front;
* resolve the wiphy by dumping — never hardcode a phy index;
* one `lunatik` operation at a time; the authenticator's percpu form is loaded with
  `lunatik run <script> percpu`.

## Manual smoke test

Before trusting a phase, drive it by hand once on hwsim:

```sh
sudo modprobe mac80211_hwsim radios=2
# bring up the AP via the kernel script (phase under test), then:
sudo wpa_supplicant -i wlan1 -c /tmp/sta.conf -d          # the client
sudo wpa_cli -i wlan1 status | grep wpa_state             # COMPLETED?
sudo iw dev ap0 station dump                              # the client, authorized?
# for WPA2: ping across the link to prove the pairwise key works
sudo rmmod mac80211_hwsim
```

Never run this against a radio on a network you care about: it stands up a rogue
AP on a real channel.

[#678]: https://github.com/luainkernel/lunatik/pull/678

