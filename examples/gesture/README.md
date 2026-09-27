# gesture

[gesture](driver.lua)
is a kernel script that implements a HID driver for the QEMU USB Tablet (0627:0001), whose reports carry an absolute 16-bit position.
It supports gestures: swiping right locks the mouse, and swiping left unlocks it.

## Usage

1. You need to change the display protocol into `VNC` and give the QEMU guest a USB tablet; the following libvirt domain XML can help you disable the PS/2 mouse and add the USB tablet:

```
<features>
	<!-- ... -->
	<ps2 state="off"/>
	<!-- ... -->
</features>
<devices>
	<!-- ... -->
	<input type="tablet" bus="usb"/>
	<!-- ... -->
</devices>
```

2. run the gesture script:

```
sudo make install         			# installs Lunatik and the examples
sudo lunatik run --context=softirq examples/gesture/driver 	# runs gesture
# In QEMU window, a drag is a move with the left button held:
# Drag right to lock the mouse
# Drag left to unlock the mouse
sudo lunatik stop examples/gesture/driver	# stops gesture
```

