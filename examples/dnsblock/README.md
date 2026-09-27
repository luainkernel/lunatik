# dnsblock

**dnsblock** is a kernel script that uses the netfilter framework ([luanetfilter](https://luainkernel.github.io/lunatik/modules/netfilter.html)) to filter DNS packets.
This script drops any outbound DNS packet with question matching the blacklist provided by the user. By default, it will block DNS resolutions for the domains `github.com` and `gitlab.com`.

## Usage

```
sudo make install                      # installs Lunatik and the examples
sudo lunatik run --context=softirq examples/dnsblock/nf_dnsblock	# runs the Lua kernel script
sudo lunatik run --context=softirq --percpu examples/dnsblock/nf_dnsblock	# or one runtime per CPU, sharing the hook
```

