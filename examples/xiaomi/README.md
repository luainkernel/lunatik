# xiaomi

[xiaomi](driver.lua)
is a kernel script that ports the Xiaomi Silent Mouse driver to Lua using `luahid`.
It fixes the report descriptor for the device (`0x2717`:`0x5014`).

## Usage

The kernel's own `hid-xiaomi` driver handles the same device, and a mouse it has bound never reaches
this one: if `lsmod | grep hid_xiaomi` lists it, unload it with `sudo modprobe -r hid-xiaomi` before
running the script.

```
sudo make install         		# installs Lunatik and the examples
sudo lunatik run --context=softirq examples/xiaomi/driver 	# runs xiaomi driver
```

Then insert the Xiaomi Silent Mouse with bluetooth mode on and it should work properly.
Only the Bluetooth mode (bus `0x05`) is matched.

Stop it with:

```
sudo lunatik stop examples/xiaomi/driver
```

