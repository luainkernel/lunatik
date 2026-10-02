# dropreason

[dropreason](monitor.lua) answers "why is my packet dying?":
a kprobe on the out-of-line drop path reads the drop reason off the probed
function's arguments and counts the drops that reach it by name
(`linux.dropreason`) in an RCU table published on the shared environment
(`lunatik._ENV`). That path is `sk_skb_reason_drop(sk, skb, reason)` from v6.11,
where `kfree_skb_reason(skb, reason)` became a static inline over it, so the
script probes whichever symbol `linux.lookup()` finds and reads the reason from
the argument that goes with it; when neither exists, it names both instead of
failing as a registration error. A drop freed from hardirq
(`dev_kfree_skb_any()`) or as a segment list (`kfree_skb_list()`) takes another
path and is not counted.
[report](report.lua) reads those counts live from the REPL.
The script logs the symbol it settled on to `dmesg` as it arms, and the first
drop matching `WATCH` also has its registers and call trace dumped there, which
is what names the drop site.

## Usage

Needs a kernel with `CONFIG_KPROBES` on an architecture that selects
`CONFIG_HAVE_FUNCTION_ARG_ACCESS_API`, as x86 and arm64 do, since the script reads
the reason through `regs:argument`. The trigger line is a bash
redirection.

```
sudo make install                                              # installs Lunatik and the examples
sudo lunatik run --context=hardirq examples/dropreason/monitor  # arms the kprobe
echo x > /dev/udp/127.0.0.1/9999                                # trigger a NO_SOCKET drop
sudo lunatik                                                    # opens the kernel REPL
> drops = require("examples.dropreason.report")
> drops.NO_SOCKET
1
> drops.report()                                                # counts by reason
      1  NO_SOCKET
      6  TCP_OLD_DATA
    152  NOT_SPECIFIED
sudo lunatik stop examples/dropreason/monitor
```

