# shared

[shared](daemon.lua)
is a kernel script that implements an in-memory key-value store using
[rcu](https://luainkernel.github.io/lunatik/modules/rcu.html),
[data](https://luainkernel.github.io/lunatik/modules/data.html),
[socket](https://luainkernel.github.io/lunatik/modules/socket.html) and
[thread](https://luainkernel.github.io/lunatik/modules/thread.html).
It serves one connection at a time on 127.0.0.1:90. Keys and values are alphanumeric: `key=value`
assigns, `key=` with no value deletes the key, `key` retrieves it, and a line with no key ends the
session.

## Usage

```
sudo make install                 # installs Lunatik and the examples
sudo lunatik spawn examples/shared/daemon # spawns shared
nc 127.0.0.1 90                    # connects to shared
foo=bar                            # assigns "bar" to foo
foo                                # retrieves foo
bar
nokey                              # retrieves a key that was never assigned
                                   # answers with an empty line
^C                                 # finishes the connection
sudo lunatik stop examples/shared/daemon # stops shared
```

