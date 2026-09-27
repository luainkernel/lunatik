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

Run it on a test machine or a VM. `setup.sh` turns IPv4 and IPv6 forwarding on, and while IPv6
forwarding is on the kernel ignores router advertisements unless `accept_ra` is 2, so a host that
takes its IPv6 default route from them loses it when the route's lifetime runs out. `cleanup.sh` turns
both kinds of forwarding off rather than back to what they were, so a host that forwarded before, a
container or VM host, has to turn it on again. The host needs a default route for each family, since a
packet with no route is never forwarded and the hook never sees it.

## Usage

```
sudo make install                      # installs Lunatik and the examples
sudo examples/tcpreject/setup.sh        # sets up namespace, nft mark rule, and loads the hook

# connection is reset immediately (IPv4)
sudo ip netns exec tcpreject curl --connect-timeout 2 https://8.8.8.8

# connection is reset immediately (IPv6)
sudo ip netns exec tcpreject curl --connect-timeout 2 https://[2001:4860:4860::8888]

# cleanup
sudo examples/tcpreject/cleanup.sh
```

