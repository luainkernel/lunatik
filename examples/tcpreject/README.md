# tcpreject

**tcpreject** is a kernel script that uses the
netfilter framework ([luanetfilter](https://luainkernel.github.io/lunatik/modules/netfilter.html))
and the socket buffer API ([luaskb](https://luainkernel.github.io/lunatik/modules/skb.html))
to inject a TCP RST toward the origin of forwarded packets.

It intercepts packets marked by an `nft` rule, builds a RST+ACK by
copying the original packet, inverting IP, MAC, and port addresses,
trimming the payload, and recomputing the checksums.
It supports both IPv4 and IPv6.
By default, it rejects forwarded HTTPS (TCP/443) connections to `8.8.8.8` (IPv4)
and `2001:4860:4860::8888` (IPv6).

## Usage

```
sudo make examples_install              # installs examples
sudo examples/tcpreject/setup.sh        # sets up namespace, nft mark rule, and loads the hook

# connection is reset immediately (IPv4)
ip netns exec tcpreject curl --connect-timeout 2 https://8.8.8.8

# connection is reset immediately (IPv6)
ip netns exec tcpreject curl --connect-timeout 2 https://[2001:4860:4860::8888]

# cleanup
sudo examples/tcpreject/cleanup.sh
```

