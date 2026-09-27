# systrack

[systrack](probe.lua)
is a kernel script that uses kprobes to count each system call of the running
architecture whose entry point no other entry of the syscall table shares: aliases
and the not-implemented stub are skipped. It needs a kernel with `CONFIG_KPROBES`.
[systrack/device](device.lua)
exposes the live counters as a character device readable with `cat`.

The device runtime creates the probe runtime via `runner.run`, passing the
RCU counter table via `runtime:resume()`. Stopping the device runtime also
stops the probe runtime.

## Usage

```
sudo make install                                    # installs Lunatik and the examples
sudo lunatik run examples/systrack/device             # starts device and probe runtimes
cat /dev/systrack
close: 473
openat: 515
read: 1066
write: 438
sudo lunatik stop examples/systrack/device            # stops device and probe runtimes
```

