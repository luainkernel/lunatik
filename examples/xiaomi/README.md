# xiaomi

[xiaomi](driver.lua)
is a kernel script that ports the Xiaomi Silent Mouse driver to Lua using `luahid`.
It fixes the report descriptor for the device (`0x2717`:`0x5014`).

## Usage

```
sudo make examples_install 		# installs examples
sudo lunatik run examples/xiaomi/driver softirq 	# runs xiaomi driver
```

Then insert the Xiaomi Silent Mouse with bluetooth mode on and it should work properly.

