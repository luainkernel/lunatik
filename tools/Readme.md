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
