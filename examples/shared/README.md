# shared

[shared](daemon.lua)
is a kernel script that implements an in-memory key-value store using
[rcu](https://luainkernel.github.io/lunatik/modules/rcu.html),
[data](https://luainkernel.github.io/lunatik/modules/data.html),
[socket](https://luainkernel.github.io/lunatik/modules/socket.html) and
[thread](https://luainkernel.github.io/lunatik/modules/thread.html).

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
```

