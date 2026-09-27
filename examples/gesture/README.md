# gesture

[gesture](driver.lua)
is a kernel script that implements a HID driver for QEMU USB Mouse (0627:0001).
It supports gestures: swiping right locks the mouse, and swiping left unlocks it.

## Usage

1. You need to change the display protocal into `VNC` and enable USB mouse device in QEMU, the following configuration can help you disable PS2 mouse & enable USB mouse:

```
<features>
	<!-- ... -->
	<ps2 state="off"/>
	<!-- ... -->
</features>
```

2. run the gesture script:

```
sudo make install         			# installs Lunatik and the examples
sudo lunatik run --context=softirq examples/gesture/driver 	# runs gesture
# In QEMU window:
# Drag right to lock the mouse
# Drag left to unlock the mouse
```

