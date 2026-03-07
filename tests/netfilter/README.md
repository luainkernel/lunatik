# netfilter tests

Integration tests for the `netfilter` and `skb` modules.
Each test is a shell script that loads a kernel Lua script via `lunatik run`,
generates relevant traffic from userspace, and verifies the result.

## Requirements

- Lunatik modules loaded (`sudo lunatik load`)
- Lua scripts installed (`sudo make tests_install`)
- Root privileges
- Network connectivity to `8.8.8.8`
- `host(1)` (dnsutils)

## Tests

### drop_dns

Loads a minimal hook that drops all outgoing UDP port 53 packets.
Verifies DNS queries fail while the hook is active, then pass after unload.

```
sudo bash tests/netfilter/drop_dns.sh
```

### dnsblock

Loads `examples/dnsblock/nf_dnsblock`. Verifies that blocklisted domains
(`github.com`, `gitlab.com`) are dropped and unlisted domains (`google.com`)
still resolve. Verifies all domains resolve again after unload.

```
sudo bash tests/netfilter/dnsblock.sh
```

### dnsdoctor (smoke test)

Loads `examples/dnsdoctor/nf_dnsdoctor` and verifies clean register/unregister.
Full integration testing (DNS response rewriting for `lunatik.com → 10.1.2.3`)
requires a DNS server at `10.1.1.2` and is out of scope here.

```
sudo bash tests/netfilter/dnsdoctor.sh
```

