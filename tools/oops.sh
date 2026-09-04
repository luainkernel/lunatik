#!/bin/bash
# Captures the last kernel oops before a reboot takes it away: the dmesg block from the fault
# to "end trace", the instructions around the faulting one in the installed module, and the
# processes left in D state. Prints to stdout; keep it under scratch/, not /tmp, which the
# reboot clears too.
# Usage: tools/oops.sh [dmesg-dump] > scratch/oops-$(date +%F).txt

src="$1"

dump() {
	if [ -n "$src" ]; then cat "$src"; else dmesg; fi
}

block=$(dump | awk '/Unable to handle|BUG: |Internal error/ { f=1 } f { print } /end trace/ { f=0 }')
[ -n "$block" ] || { echo "no oops in dmesg" >&2; exit 1; }
echo "$block"

pc=$(echo "$block" | sed -n 's/.*pc : \([A-Za-z0-9_]*\)+0x\([0-9a-f]*\)\/0x[0-9a-f]* \[\([A-Za-z0-9_]*\)\].*/\1 \2 \3/p' | head -1)
if [ -n "$pc" ]; then
	read -r sym off mod <<< "$pc"
	ko=$(modinfo -n "$mod" 2>/dev/null)
	if [ -n "$ko" ] && command -v objdump > /dev/null 2>&1; then
		echo
		echo "== $mod: $sym+0x$off in $ko (the installed build; it must be the one that crashed)"
		listing=$(objdump -d --no-show-raw-insn "$ko" | awk -v s="<$sym>:" '$0 ~ s { f=1 } f && /^$/ { exit } f')
		base=$(echo "$listing" | head -1 | cut -d' ' -f1)
		target=$(printf '%x' $((16#$base + 16#$off)))
		echo "$listing" | grep -n -E "^ *$target:" | cut -d: -f1 | head -1 | while read -r n; do
			echo "$listing" | sed -n "$((n > 8 ? n - 8 : 1)),$((n + 4))p" | sed "s/^ *$target:/=> &/"
		done
	fi
fi

echo
echo "== processes in D state"
ps -eo pid,stat,etime,cmd | awk '$2 ~ /D/'

