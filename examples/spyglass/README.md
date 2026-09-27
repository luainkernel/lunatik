# spyglass

**spyglass**
is a kernel script that implements a _keylogger_ inspired by the
[spy](https://github.com/jarun/spy) kernel module.
This kernel script logs the _keysym_ of the pressed keys in a device (`/dev/spyglass`).
If the _keysym_ is a printable character, `spyglass` logs the _keysym_ itself;
otherwise, it logs a mnemonic of the ASCII code, (e.g., `<del>` stands for `127`).

The keyboard notifier fires in hardirq context, whereas the device requires
process context; spyglass splits across two runtimes
([`device.lua`](device.lua) in process and
[`notifier.lua`](notifier.lua) in hardirq) sharing captured
chars via a [`fifo`](../../lib/luafifo.c).

## Usage

```
sudo make install                         # installs Lunatik and the examples
sudo lunatik run examples/spyglass/device  # runs spyglass
sudo tail -f /dev/spyglass                 # prints the key log
```

