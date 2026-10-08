# dnsdoctor

**dnsdoctor** is a kernel script that uses the netfilter framework ([luanetfilter](https://luainkernel.github.io/lunatik/modules/netfilter.html)) to change the DNS response
from Public IP to a Private IP if the destination IP matches the one provided by the user. For example, if the user
wants to change the DNS response from `192.168.10.1` to `10.1.2.3` for the domain `lunatik.com` if the query is being sent to `10.1.1.2` (a private client), this script can be used.
The domain, the address it rewrites to and the client are set in [nf_dnsdoctor.lua](nf_dnsdoctor.lua), not given when it runs.

## Usage

Needs `dnsmasq` and `dig`. `setup.sh` points the host's `/etc/resolv.conf` at `10.1.1.3`, saving it
as `/etc/resolv.conf.lunatik`, and only `cleanup.sh` puts it back: run `cleanup.sh` even after
stopping `setup.sh` with Ctrl-C, or the host keeps resolving through a server that is gone.
`setup.sh` keeps dnsmasq in the foreground and does not return, so the rest runs in a second terminal.

In the first terminal:

```
sudo make install                      # installs Lunatik and the examples
examples/dnsdoctor/setup.sh             # sets up the environment, dnsmasq serving the zone
```

In the second one:

```
# test the setup, a response with IP 192.168.10.1 should be returned
dig lunatik.com

# run the Lua kernel script, either in one runtime or in one runtime per CPU
sudo lunatik run --context=softirq examples/dnsdoctor/nf_dnsdoctor
sudo lunatik run --context=softirq --percpu examples/dnsdoctor/nf_dnsdoctor	# or one runtime per CPU, sharing the hook

# test the setup, a response with IP 10.1.2.3 should be returned
dig lunatik.com

# cleanup, after a Ctrl-C in the first terminal
sudo lunatik stop examples/dnsdoctor/nf_dnsdoctor
examples/dnsdoctor/cleanup.sh
```

