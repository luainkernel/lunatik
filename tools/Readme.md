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

