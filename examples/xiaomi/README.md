# xiaomi

[xiaomi](driver.lua)
is a kernel script that ports the Xiaomi Silent Mouse driver to Lua using `luahid`.
It fixes the report descriptor for the device (`0x2717`:`0x5014`).

## Usage

```
sudo make install         		# installs Lunatik and the examples
sudo lunatik run --context=softirq examples/xiaomi/driver 	# runs xiaomi driver
```

Then insert the Xiaomi Silent Mouse with bluetooth mode on and it should work properly.

