# tap

[tap](device.lua)
is a kernel script that implements a _sniffer_ using `AF_PACKET` socket.
It prints destination and source MAC addresses followed by Ethernet type and the frame size.

## Usage

```
sudo make install            # installs Lunatik and the examples
sudo lunatik run examples/tap/device # runs tap
cat /dev/tap
```

