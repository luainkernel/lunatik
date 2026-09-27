# echod

**echod**
is an echo server implemented as kernel scripts.
The [daemon](daemon.lua) listens on 127.0.0.1:1337 and hands each connection to a kernel thread running
[worker.lua](worker.lua); the workers end within 100 ms of the daemon's stop.

## Usage

```
sudo make install                       # installs Lunatik and the examples
sudo lunatik spawn examples/echod/daemon # runs echod
nc 127.0.0.1 1337
hello kernel!
hello kernel!
sudo lunatik stop examples/echod/daemon  # stops echod and its workers
```

