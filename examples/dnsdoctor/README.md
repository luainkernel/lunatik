# dnsdoctor

**dnsdoctor** is a kernel script that uses the netfilter framework ([luanetfilter](https://luainkernel.github.io/lunatik/modules/netfilter.html)) to change the DNS response
from Public IP to a Private IP if the destination IP matches the one provided by the user. For example, if the user
wants to change the DNS response from `192.168.10.1` to `10.1.2.3` for the domain `lunatik.com` if the query is being sent to `10.1.1.2` (a private client), this script can be used.

## Usage

```
sudo make examples_install              # installs examples
examples/dnsdoctor/setup.sh             # sets up the environment

# test the setup, a response with IP 192.168.10.1 should be returned
dig lunatik.com

# run the Lua kernel script
sudo lunatik run --context=softirq examples/dnsdoctor/nf_dnsdoctor
sudo lunatik run --context=softirq --percpu examples/dnsdoctor/nf_dnsdoctor	# or one runtime per CPU, sharing the hook

# test the setup, a response with IP 10.1.2.3 should be returned
dig lunatik.com

# cleanup
sudo lunatik unload
examples/dnsdoctor/cleanup.sh
```

