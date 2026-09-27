# keylocker

[keylocker](notifier.lua)
is a kernel script that implements
[Konami Code](https://en.wikipedia.org/wiki/Konami_Code)
for locking and unlocking the console keyboard.
When the user types `↑ ↑ ↓ ↓ ← → ← → LCTRL LALT`,
the keyboard will be _locked_; that is, the system will stop processing any key pressed
until the user types the same key sequence again.

The keyboard notifier fires in hardirq context, so keylocker must run in a
`hardirq` runtime (passed to `lunatik run` as `--context=hardirq`).
It needs a kernel built with `CONFIG_VT`, and only the keys of a local keyboard
reach the notifier, not input over ssh or a pty.

## Usage

```
sudo make install                                              # installs Lunatik and the examples
sudo lunatik run --context=hardirq examples/keylocker/notifier  # runs keylocker
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT>                  # locks keyboard
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT>                  # unlocks keyboard
sudo lunatik stop examples/keylocker/notifier                   # stops keylocker
```

A keyboard left locked is released by stopping the script from another session, over ssh.

