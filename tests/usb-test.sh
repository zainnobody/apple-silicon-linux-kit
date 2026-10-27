#!/bin/bash
# USB drive test for one port. Run on the M3 after the drive is plugged in.
# Usage: usb-test.sh <port-label>
# Reads the kernel log, lsusb -t and the negotiated speed. Then, with a mounted drive,
# runs one fio read and one fio write on a 1 GB temp file, and deletes the file.
PORT="${1:-unknown}"
echo "== port label: $PORT  $(date)"
echo "== typec"; for p in /sys/class/typec/port?; do echo "$p $(cat $p/data_role) $(cat $p/power_role)"; done
echo "== lsusb -t"; lsusb -t
echo "== speed (Mb/s: 480 = USB 2, 5000 = USB 3.0, 10000 = USB 3.1/3.2)"
for d in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
  [ -f "$d/speed" ] && echo "$(basename $d) $(cat $d/product 2>/dev/null) speed=$(cat $d/speed)"
done
echo "== lsblk"; lsblk -o NAME,SIZE,TRAN,FSTYPE,MOUNTPOINT | grep -v -E "zram|nvme"
echo "== kernel log (last 3 min)"; journalctl -k --since "-3min" --no-pager | grep -viE "dependency cycle" | tail -20
MNT=$(lsblk -nro MOUNTPOINT,TRAN | awk '$2=="usb" && $1!=""{print $1; exit}')
[ -z "$MNT" ] && MNT=$(findmnt -rno TARGET -S /dev/sd* 2>/dev/null | head -1)
if [ -n "$MNT" ] && [ -w "$MNT" ]; then
  F="$MNT/.fio-usb-test.bin"
  echo "== fio on $MNT"
  fio --name=w --filename="$F" --size=1G --rw=write --bs=1M --ioengine=libaio --iodepth=8 --direct=1 --group_reporting 2>&1 | grep -E "WRITE:"
  fio --name=r --filename="$F" --size=1G --rw=read  --bs=1M --ioengine=libaio --iodepth=8 --direct=1 --group_reporting 2>&1 | grep -E "READ:"
  rm -f "$F"; ls "$F" 2>&1 | tail -1
else
  echo "== no writable mounted USB drive: skip fio"
fi
