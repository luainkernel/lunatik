# systrack

[systrack](probe.lua)
is a kernel script that uses kprobes to count every system call on the
running architecture. [systrack/device](device.lua)
exposes the live counters as a character device readable with `cat`.

The device runtime creates the probe runtime via `runner.run`, passing the
RCU counter table via `runtime:resume()`. Stopping the device runtime also
stops the probe runtime.

## Usage

```
sudo make examples_install                            # installs examples
sudo lunatik run examples/systrack/device             # starts device and probe runtimes
cat /dev/systrack
close: 473
openat: 515
read: 1066
write: 438
sudo lunatik stop examples/systrack/device            # stops device and probe runtimes
```

