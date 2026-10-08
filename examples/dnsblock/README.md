# dnsblock

**dnsblock** is a kernel script that uses the netfilter framework ([luanetfilter](https://luainkernel.github.io/lunatik/modules/netfilter.html)) to filter DNS packets.
This script drops the IPv4 UDP DNS queries the host itself sends whose question name contains a blacklisted domain. By default, it will block DNS resolutions for `example.net`, a name RFC 2606 reserves, listed in [common.lua](common.lua); each entry is a Lua pattern matched against the name as it travels on the wire, so its `.` stands for any byte.
The hook reads every packet as IPv4 UDP, so queries over IPv6 or TCP are not recognized, and the queries
the host forwards never reach it.

## Usage

Run the script either in one runtime or, with `--percpu`, in one runtime per CPU sharing the hook:

```
sudo make install                      # installs Lunatik and the examples
sudo lunatik run --context=softirq examples/dnsblock/nf_dnsblock	# runs the Lua kernel script
sudo lunatik run --context=softirq --percpu examples/dnsblock/nf_dnsblock	# or one runtime per CPU, sharing the hook
```

A query for a blacklisted name then gets no answer:

```
host -4 example.net
;; communications error to 8.8.8.8#53: timed out
;; communications error to 8.8.8.8#53: timed out
;; no servers could be reached
```

Stop it with:

```
sudo lunatik stop examples/dnsblock/nf_dnsblock
```

