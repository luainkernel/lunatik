# keylocker

[keylocker](notifier.lua)
is a kernel script that implements
[Konami Code](https://en.wikipedia.org/wiki/Konami_Code)
for locking and unlocking the console keyboard.
When the user types `↑ ↑ ↓ ↓ ← → ← → LCTRL LALT`,
the keyboard will be _locked_; that is, the system will stop processing any key pressed
until the user types the same key sequence again.

The keyboard notifier fires in hardirq context, so keylocker must run in a
`hardirq` runtime (passed as the third argument to `lunatik run`).

## Usage

```
sudo make examples_install                         # installs examples
sudo lunatik run examples/keylocker/notifier hardirq # runs keylocker
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT>     # locks keyboard
<↑> <↑> <↓> <↓> <←> <→> <←> <→> <LCTRL> <LALT>     # unlocks keyboard
```

