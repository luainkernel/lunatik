# tap

[tap](device.lua)
is a kernel script that implements a _sniffer_ using `AF_PACKET` socket.
It prints destination and source MAC addresses followed by Ethernet type and the frame size.

## Usage

```
sudo make examples_install    # installs examples
sudo lunatik run examples/tap/device # runs tap
cat /dev/tap
```

