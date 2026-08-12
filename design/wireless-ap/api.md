# Proposed Lua API: the AP control plane and `wpa`

Two layers. The **control plane** extends the existing `nl80211` namespace with
the objects an AP needs — firm, because each maps to a verified nl80211 command.
The **authenticator** is a new `wpa` module — proposed, and its frame-delivery
half is deliberately left open until the phase-2 spike (see `kernel-notes.md`).

Each section is marked **[firm]** (maps to a verified command, shape settled) or
**[proposed]** (design intent, may change once prototyped).

## Conventions

Objects follow the established `netlink` pattern: a class under the namespace,
constructed with `()`, closed by `close()` or `<close>`, methods taking an options
table. `nl80211.ap`/`station`/`key` are `netlink.genl` sessions bound to the
`"nl80211"` family, exactly like `nl80211.interface`. All block and need a
sleepable runtime, except where a per-CPU dispatched path is noted.

## Control plane

### `nl80211.ap():start/stop` — [firm, in flight #680]

```lua
local ap <close> = netlink.nl80211.ap()
ap:start{ifindex = idx, freq = 2412, beacon_interval = 100, dtim = 2,
         ssid = "lab", head = beacon_head}   -- raw 802.11 beacon head
ap:stop{ifindex = idx}
```

Already proposed and validated in its own PR; listed here for completeness.

### `nl80211.station()` — [firm]

Manage associated stations. `add`/`del`/`set` by MAC; `list` dumps them.

```lua
local station <close> = netlink.nl80211.station()

station:add{ifindex = idx, mac = mac, aid = 1,
            listen_interval = 10, supported_rates = rates}
station:set{ifindex = idx, mac = mac, authorized = true}   -- open the controlled port
for _, s in ipairs(station:list(idx)) do
    -- { mac, aid, flags, ... }
end
station:del{ifindex = idx, mac = mac}
```

`set{authorized = true}` is the port-open primitive the handshake calls on
completion (`NL80211_STA_FLAG_AUTHORIZED`). `add` maps to `NL80211_CMD_NEW_STATION`
with `MAC`/`STA_AID`/`STA_LISTEN_INTERVAL`/`STA_SUPPORTED_RATES`; `set` to
`SET_STATION` with a `STA_FLAGS2` set/mask; `del` to `DEL_STATION`.

### `nl80211.key()` — [firm]

Install and remove keys.

```lua
local key <close> = netlink.nl80211.key()

key:add{ifindex = idx, mac = mac, idx = 0, cipher = cipher.CCMP,
        data = ptk_tk, seq = seq}            -- pairwise key for one station
key:add{ifindex = idx, idx = 1, cipher = cipher.CCMP, data = gtk}  -- group key (no mac)
key:del{ifindex = idx, mac = mac, idx = 0}
```

`NL80211_CMD_NEW_KEY`/`DEL_KEY` with `KEY_DATA`/`KEY_IDX`/`KEY_CIPHER`/`KEY_SEQ`;
`MAC` present means pairwise, absent means group.

## The authenticator: `wpa` — [proposed]

A module composing `nl80211` (control plane), `crypto` (handshake primitives) and
EAPOL delivery. It owns the per-station state and the per-BSS group keys, and
exposes a small surface: create an authenticator over a running AP, hand it a
policy, and let it run. The four outward operations it needs (`send_eapol`,
`set_key`, `get_psk`, `set_port_authorized`) are internal — implemented against
`key`/`station` and the delivery path — not part of the public API.

### `wpa.authenticator{...}` — [proposed]

```lua
local wpa = require("wpa")

local auth = wpa.authenticator{
    ifindex = idx,
    ssid    = "lab",
    akm     = wpa.akm.PSK,          -- WPA2-PSK (only PSK and OPEN initially)
    cipher  = wpa.cipher.CCMP,
    -- association policy: plain Lua, hot-reloadable, evaluated per station
    policy  = function(sta)
        -- sta = { mac, rssi, ies, ... }; return the PSK to admit, or nil to reject
        if blocked[sta.mac] then return nil end
        return passphrase           -- get_psk
    end,
}
```

The `policy` callback is `get_psk` and the association decision fused: returning a
passphrase admits the station and seeds its 4-way handshake; returning `nil`
rejects it. This is the programmable-policy point — policy in the association
path, hot-reloadable, with no userspace round trip — and where band-steering or
per-client parameters would live.

### Per-station state — [proposed]

Kept in a shared `rcu.table` keyed by STA MAC, because delivery is per-CPU by
arrival, not per-STA (see `kernel-notes.md` §5–6). Each entry is one 4-way FSM:
`state`, `anonce`/`snonce`, `pmk`/`ptk`, `replay`, and a retransmit deadline. The
per-BSS group key (GTK) and its rekey are owned by one runtime.

The FSM itself is a direct transcription of `hostapd`'s `WPA_PTK` ladder
(`kernel-notes.md` §4): a `step(sta, event)` that runs to a fixpoint and calls out
to `key:add` (install PTK/GTK), `station:set{authorized}` (open the port), and the
EAPOL sender.

### EAPOL delivery — [open, decided by phase 2]

The one piece intentionally unspecified here. The authenticator needs an inbound
"an EAPOL frame arrived from MAC X" event and an outbound "send this EAPOL frame to
MAC X". Both the control-port path (§3a) and the per-CPU packet-path (§3b/A) can
provide them; which one, and therefore whether the authenticator is a plain
runtime or a `percpu` script, is the phase-2 result. The `wpa` API above is written
to not depend on the answer: the handshake logic is the same either way, only the
transport binding under `send_eapol`/the RX event differs.

## Worked example: a WPA2-PSK AP in Lua

Ties the layers together. Bring up the radio, start beaconing, run the
authenticator with a policy. (Phases 0–3; the `percpu` form is phase 4.)

```lua
local netlink = require("netlink")
local wpa     = require("wpa")

local SSID <const> = "lunatik-lab"
local PSK  <const> = "correct horse battery staple"

-- 1. create an AP interface on the first radio and bring it up
local ifindex
do
    local wiphy     <close> = netlink.nl80211.wiphy()
    local interface <close> = netlink.nl80211.interface()
    ifindex = interface:add{wiphy = wiphy:list()[1].wiphy, name = "ap0",
                            iftype = require("linux.nl80211").iftype.AP}
end
netlink.rt.link():set{ifindex = ifindex, up = true}

-- 2. beacon (minimal open-enough head; RSN IE in the tail advertises WPA2)
netlink.nl80211.ap():start{ifindex = ifindex, freq = 2412,
    beacon_interval = 100, dtim = 2, ssid = SSID,
    head = wpa.beacon_head{ssid = SSID, channel = 1},
    tail = wpa.beacon_tail{akm = wpa.akm.PSK, cipher = wpa.cipher.CCMP}}

-- 3. the authenticator: admit anyone with the PSK, reject a blocklist
local auth = wpa.authenticator{
    ifindex = ifindex, ssid = SSID, akm = wpa.akm.PSK, cipher = wpa.cipher.CCMP,
    policy = function(sta)
        return not blocked[sta.mac] and PSK or nil
    end,
}
```

A real client (`wpa_supplicant -c ...`) then associates and completes WPA2-PSK
against this script. The policy is ordinary Lua: editing `blocked` and reloading
changes admission with no daemon restart and no userspace round trip on the
association path — the point of putting the policy in the kernel.

The example shows `ap:start` and `wpa.authenticator` as separate steps. If the
phase-2 result is the control-port path, START_AP must be sent by the socket that
then receives EAPOL (`kernel-notes.md` §3a), so the authenticator would own the AP
bring-up rather than take an already-started interface. Which of the two this
becomes is, again, the phase-2 result; the split above is the open-AP form.

## Autogen additions

New constants for `linux.nl80211`, added per phase (not all at once — `linux.*` is
published API, and a table with no consumer freezes a shape too early):

* phase 0: `STA_FLAGS2`, `STA_AID`, `STA_LISTEN_INTERVAL`, `STA_SUPPORTED_RATES`,
  `KEY_DATA`, `KEY_IDX`, `KEY_CIPHER`, `KEY_SEQ`, `KEY_TYPE` attributes; the
  `NL80211_STA_FLAG_*` and `WLAN_CIPHER_SUITE_*`/`WLAN_AKM_SUITE_*` values;
* phase 1: `REGISTER_FRAME`, `FRAME`, `FRAME_TX_STATUS` and the frame-type/auth
  attributes;
* phase 2/3: `CONTROL_PORT_FRAME`, `CONTROL_PORT_OVER_NL80211`,
  `CONTROL_PORT_ETHERTYPE`, `SOCKET_OWNER` — only once the delivery path is chosen.

The `wpa.akm`/`wpa.cipher` tables are thin Lua aliases over the generated
`WLAN_AKM_SUITE_*`/`WLAN_CIPHER_SUITE_*` values, named for the API's vocabulary.

