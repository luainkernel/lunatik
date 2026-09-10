# Additional tools

## debian_kernel_postinst_lunatik.sh

Under Debian, copy this script into /etc/kernel/postinst.d/
to have Lunatik installed on kernel upgrade:

```sh
sudo cp debian_kernel_postinst_lunatik.sh /etc/kernel/postinst.d/zz-update-lunatik
sudo chmod +x /etc/kernel/postinst.d/zz-update-lunatik
```

To check it works:

```sh
sudo dpkg-reconfigure linux-image-`uname -r`
```

## oops.sh

Captures the last kernel oops before a reboot takes it away: the `dmesg` block, the instructions
around the faulting one in the installed module, and the processes left in D state.

```sh
tools/oops.sh > scratch/oops-$(date +%F).txt
```

A saved dump, `journalctl -k -b -1 -o cat` after the reboot where the journal is persistent,
is read the same way: `tools/oops.sh <dump>`.

## watchdog.sh

Runs a Lunatik script and stops it if the host loses the connectivity it had before the run,
the loopback or the default route's gateway; a script that cuts the machine off cannot be
stopped by hand afterwards.

```sh
sudo bash tools/watchdog.sh examples/ifquarantine/control
sudo LUNATIK_WATCHDOG_GRACE=10 bash tools/watchdog.sh examples/filter/sni softirq percpu
```

