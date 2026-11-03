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

Run it on a test machine or a VM. `setup.sh` turns IPv4 and IPv6 forwarding on, and as IPv6
forwarding turns on the kernel drops the default routes learned from router advertisements and ignores
new ones unless `accept_ra` is 2, so a host that takes its IPv6 default route from them loses it.
`cleanup.sh` puts both kinds of forwarding back to the values `setup.sh` found, which it keeps in
`/run/tcpreject.sysctl`; without that file, as after a reboot, it leaves forwarding as it is. It
does not bring back `default` and per-device forwarding values that differed from `all`, which every
IPv6 write to `all` overwrites, and an IPv4 one when `ip_forward` changes. On a host that did not
forward, it does not bring back IPv4 `conf/all/accept_redirects`, which the kernel sets to the
opposite of `ip_forward`, nor large receive offload, which turning forwarding on disables on every
device, and the IPv6 default route comes back only with the next router advertisement. The host
needs a default route for each family, since a packet with no route is never forwarded and the hook
never sees it.

## Usage

```
sudo make install                      # installs Lunatik and the examples
sudo examples/tcpreject/setup.sh        # sets up namespace and nft mark rule
sudo lunatik run --context=softirq examples/tcpreject/nf_tcpreject	# loads the hook

# connection is reset immediately (IPv4)
sudo ip netns exec tcpreject curl --connect-timeout 2 https://8.8.8.8

# connection is reset immediately (IPv6)
sudo ip netns exec tcpreject curl --connect-timeout 2 https://[2001:4860:4860::8888]

# cleanup
sudo examples/tcpreject/cleanup.sh
```

