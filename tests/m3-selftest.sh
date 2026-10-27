#!/bin/bash
# M3 self-test: every check that needs no hands, one line each (PASS, WARN, FAIL, SKIP).
# Run on the M3 as the desktop user (sudo -n is used for root reads when it works).
#   m3-selftest.sh            all checks, 20 s GPU load, 2 s camera capture
#   m3-selftest.sh --quick    no GPU load, no camera capture
#   m3-selftest.sh --full     adds a short llama.cpp run (about 1 min of GPU load)
# Writes ~/selftest/selftest-<time>.log and ~/selftest/last.json. Exit code = number of FAILs.
set -u
MODE=normal
case "${1:-}" in --quick) MODE=quick;; --full) MODE=full;; "") ;; *) echo "usage: $0 [--quick|--full]"; exit 2;; esac
OUT=$HOME/selftest; mkdir -p "$OUT"; TS=$(date +%Y%m%d-%H%M%S); LOG=$OUT/selftest-$TS.log
exec > >(tee "$LOG") 2>&1
NF=0; NW=0; NP=0; JSON=()
r() { # r <PASS|WARN|FAIL|SKIP> <area> <name> <detail>
	printf '%-4s %-9s %-22s %s\n' "$1" "$2" "$3" "$4"
	case $1 in PASS) NP=$((NP+1));; WARN) NW=$((NW+1));; FAIL) NF=$((NF+1));; esac
	local d=${4//\\/\\\\}; d=${d//\"/\\\"}
	JSON+=("{\"result\":\"$1\",\"area\":\"$2\",\"name\":\"$3\",\"detail\":\"$d\"}")
}
SU() { sudo -n "$@" 2>/dev/null; }
hw() { grep -l "^$1\$" /sys/class/hwmon/hwmon*/name 2>/dev/null | head -1 | xargs -r dirname; }
# Audio, camera and video decode need a desktop login: logind gives device access to the active seat user only.
SEATED=0
for sid in $(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$(id -u)" '$2==u{print $1}'); do
	[ "$(loginctl show-session "$sid" -p Seat --value 2>/dev/null)" = seat0 ] && [ "$(loginctl show-session "$sid" -p Active --value 2>/dev/null)" = yes ] && SEATED=1
done
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
echo "m3-selftest $TS, mode $MODE, kernel $(uname -r), up $(uptime -p | sed 's/^up //')"

# ---- boot
STAGEE=f3197272d588f4b0a037c5f81f0cfb2c36dfc6c7398a4205910ed8b9cbaa0725
[ "$(uname -r)" = 7.2.11-m3gpu+ ] && r PASS boot kernel "$(uname -r)" || r WARN boot kernel "$(uname -r) (expected 7.2.11-m3gpu+)"
bb=$(SU sha256sum /boot/efi/m1n1/boot.bin | cut -d' ' -f1)
if [ -z "$bb" ]; then r SKIP boot boot.bin "no sudo -n"
elif [ "$bb" = $STAGEE ]; then r PASS boot boot.bin "stageE"
else r WARN boot boot.bin "${bb:0:16} is not stageE (a test boot armed?)"; fi
nfail=$(systemctl --failed --no-legend --plain 2>/dev/null | wc -l)
[ "$nfail" -eq 0 ] && r PASS boot failed-units 0 || r FAIL boot failed-units "$nfail: $(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')"
# Kernel errors this boot, without the lines that are known and harmless on this Mac
# bpf-restrict-fs: this kernel has no BPF LSM, so systemd's RestrictFileSystems cannot load (harmless)
KNOWN='bpf-restrict-fs|apple-dcp|brcmf_.*-52|p2p-dev-wld0|p2p_disc|Failed to read codec capabilities|join_pref|assoc info'
kerr=$(SU journalctl -k -b -p err --no-pager -o cat | grep -vE "$KNOWN")
[ -z "$kerr" ] && r PASS boot kernel-errors "none outside the known list" || r WARN boot kernel-errors "$(echo "$kerr" | wc -l) new: $(echo "$kerr" | head -2 | tr '\n' '|' | cut -c1-160)"

# ---- services we installed
[ "$(systemctl is-active m3-fancurve 2>/dev/null)" = active ] && r PASS service fan-curve active || r FAIL service fan-curve "not active"
[ "$(cat /sys/module/macsmc_hwmon/parameters/fan_control 2>/dev/null)" = Y ] && r PASS service fan-control Y || r FAIL service fan-control "not Y"
[ "$(systemctl --user is-active gpu-fault-watch 2>/dev/null)" = active ] && r PASS service gpu-fault-watch active || r WARN service gpu-fault-watch "not active"
[ -x /usr/lib/systemd/system-sleep/90-agx-wifi-recover ] && r PASS service sleep-wifi-hook installed || r WARN service sleep-wifi-hook "not installed"

# ---- heat and fans
FAN=$(hw macsmc_hwmon); DIE=$(hw macsmc_soc_die); HOT=$(hw apple_pmp_hotspot)
d=$(( $(cat "$DIE/temp1_input" 2>/dev/null || echo 0) / 1000 )); h=$(( $(cat "$HOT/temp1_input" 2>/dev/null || echo 0) / 1000 ))
if [ "$d" -eq 0 ]; then r FAIL heat sensors "SoC die sensor unreadable"
elif [ "$h" -ge 90 ]; then r WARN heat temps "SoC die $d C, hotspot $h C (hot at test start)"
else r PASS heat temps "SoC die $d C, hotspot $h C"; fi
f1=$(cat "$FAN/fan1_input" 2>/dev/null); f2=$(cat "$FAN/fan2_input" 2>/dev/null)
[ -n "$f1" ] && [ -n "$f2" ] && r PASS heat fans "fan1 $f1 rpm, fan2 $f2 rpm (readable)" || r FAIL heat fans "unreadable"

# ---- power
B=/sys/class/power_supply/macsmc-battery
st=$(cat $B/status 2>/dev/null); cap=$(cat $B/capacity 2>/dev/null)
ac=$(cat /sys/class/power_supply/macsmc-ac/online 2>/dev/null)
[ -n "$cap" ] && r PASS power battery "$st, $cap %" || r FAIL power battery "unreadable"
[ "$ac" = 1 ] && r PASS power charger "online" || r WARN power charger "not online (status $st)"

# ---- storage
if findmnt -n /data >/dev/null; then
	fr=$(df --output=pcent /data | tail -1 | tr -d ' %'); r PASS storage /data "mounted, ${fr}% used"
else r FAIL storage /data "not mounted"; fi
sm=$(SU smartctl -H /dev/nvme0n1 | grep -i "overall-health\|SMART Health Status" | awk -F: '{print $2}' | xargs)
if [ -z "$sm" ]; then r SKIP storage smart "no sudo -n or no output"
elif [ "$sm" = PASSED ] || [ "$sm" = OK ]; then r PASS storage smart "$sm"
else r FAIL storage smart "$sm"; fi

# ---- network and Bluetooth
[ "$(nmcli -t -f STATE general 2>/dev/null)" = connected ] && r PASS net state connected || r FAIL net state "$(nmcli -t -f STATE general 2>/dev/null)"
wl=$(nmcli -t -f DEVICE,STATE d 2>/dev/null | grep '^wld0:' | cut -d: -f2)
[ "$wl" = connected ] && r PASS net wifi "wld0 connected$(iw dev wld0 link 2>/dev/null | awk '/tx bitrate/{print ", tx "$3" "$4}')" || r WARN net wifi "wld0 ${wl:-missing}"
ping -c 2 -W 2 1.1.1.1 >/dev/null 2>&1 && r PASS net internet "ping OK" || r WARN net internet "no ping reply"
bt=$(timeout 5 bluetoothctl show 2>/dev/null | awk '/Powered:/{print $2}')
[ "$bt" = yes ] && r PASS net bluetooth "powered" || r FAIL net bluetooth "powered=${bt:-unknown}"

# ---- audio, display
if [ $SEATED = 0 ]; then
	r SKIP audio sinks "no desktop login (login screen owns the audio devices)"; r SKIP audio mics "no desktop login"
else
ns=$(pactl list short sinks 2>/dev/null | wc -l); nsrc=$(pactl list short sources 2>/dev/null | grep -vc monitor)
[ "$ns" -gt 0 ] && r PASS audio sinks "$ns ($(pactl get-default-sink 2>/dev/null))" || r FAIL audio sinks 0
[ "$nsrc" -gt 0 ] && r PASS audio mics "$nsrc input(s)" || r FAIL audio mics 0
fi
edp=$(cat /sys/class/drm/card*-eDP-1/status 2>/dev/null | head -1)
[ "$edp" = connected ] && r PASS display panel "eDP connected" || r FAIL display panel "eDP ${edp:-missing}"
if pgrep -u "$(id -u)" -x kwin_wayland >/dev/null; then r PASS display desktop "your KWin is running"
elif pgrep -x kwin_wayland >/dev/null; then r WARN display desktop "login screen only: nobody is logged in on the desktop"
else r FAIL display desktop "no KWin"; fi

# ---- ports
lsmod | grep -q '^thunderbolt_apple' && r PASS ports usb4-module loaded || r WARN ports usb4-module "not loaded"
np=$(ls -d /sys/class/typec/port* 2>/dev/null | wc -l)
[ "$np" -ge 3 ] && r PASS ports typec "$np ports" || r WARN ports typec "$np ports"

# ---- camera
CAMDEV=$(for v in /sys/class/video4linux/video*; do [ "$(cat $v/name 2>/dev/null)" = apple-isp ] && echo /dev/$(basename $v) && break; done)
if [ -z "$CAMDEV" ]; then r FAIL camera node "no apple-isp video node"
elif [ $SEATED = 0 ]; then r SKIP camera capture "no desktop login ($CAMDEV present)"
elif [ $MODE = quick ]; then r SKIP camera capture "--quick ($CAMDEV present)"
elif fuser "$CAMDEV" >/dev/null 2>&1; then r SKIP camera capture "$CAMDEV in use by another program"
else
	n=$(timeout -k 5 20 ffmpeg -nostdin -hide_banner -f v4l2 -i "$CAMDEV" -t 2 -f null - 2>&1 | grep -o 'frame= *[0-9]*' | tail -1 | grep -o '[0-9]*$')
	[ "${n:-0}" -ge 30 ] && r PASS camera capture "$n frames in 2 s" || r FAIL camera capture "${n:-0} frames in 2 s"
fi

# ---- video decode (VA-API layer in ~/.local)
VADRV=$(dirname "$(ls ~/.local/lib*/dri/v4l2_request_drv_video.so 2>/dev/null | head -1)")
if [ "$VADRV" = . ]; then r SKIP video vaapi "driver not found in ~/.local"
elif [ $SEATED = 0 ]; then r SKIP video vaapi "no desktop login (decoder device belongs to the login screen)"
elif LIBVA_DRIVERS_PATH=$VADRV LIBVA_DRIVER_NAME=v4l2_request timeout 20 ffmpeg -nostdin -hide_banner -init_hw_device vaapi=va -f lavfi -i nullsrc=s=64x64 -frames:v 1 -f null - >/dev/null 2>&1
then r PASS video vaapi "v4l2_request driver initialises"
else r FAIL video vaapi "init failed"; fi

# ---- GPU
MESA=/opt/mesa-m3
export LD_LIBRARY_PATH=$MESA/lib64 VK_DRIVER_FILES=$MESA/share/vulkan/icd.d/asahi_icd.aarch64.json
dev=$(timeout 20 vulkaninfo --summary 2>/dev/null | awk -F= '/deviceName/{print $2; exit}' | xargs)
[ -n "$dev" ] && r PASS gpu vulkan "$dev" || r FAIL gpu vulkan "no Vulkan device"
if [ $MODE = quick ]; then r SKIP gpu load "--quick"
elif [ -x ~/vktest/vk-stress ]; then
	o=$(cd ~/vktest && timeout -k 5 60 stdbuf -oL ./vk-stress 20 2>&1)
	line=$(echo "$o" | grep -o 'frames .*wrong samples [0-9]*' | tail -1)
	g=$(echo "$line" | grep -o '[0-9.]* Gpix' | cut -d' ' -f1); w=$(echo "$line" | grep -o 'wrong samples [0-9]*' | grep -o '[0-9]*$')
	if echo "$o" | grep -q STRESS_PASS && [ "${w:-1}" -eq 0 ]; then r PASS gpu load "20 s, ${g:-?} G, 0 wrong"
	else r FAIL gpu load "${line:-no result} $(echo "$o" | tail -1)"; fi
	SU journalctl -k --since "-90s" --no-pager -o cat | grep -qE 'GPU fault|fail-stop' && r FAIL gpu faults "GPU fault during the load" || r PASS gpu faults "none during the load"
else r SKIP gpu load "no ~/vktest/vk-stress"; fi

# ---- local AI (--full only)
if [ $MODE = full ]; then
	LB=$(ls ~/llm-work/llama.cpp/build*/bin/llama-bench 2>/dev/null | head -1)
	M=$(ls ~/llm-work/models/*3[Bb]*Q4_0*.gguf ~/llm-work/models/*3[Bb]*q4_0*.gguf 2>/dev/null | head -1)
	if [ -z "$LB" ] || [ -z "$M" ]; then r SKIP ai llama "no llama-bench or 3B Q4_0 model"
	else
		o=$(timeout -k 5 300 "$LB" -m "$M" -p 512 -n 64 -r 1 2>/dev/null)
		pp=$(echo "$o" | awk -F'|' '/pp512/{print $(NF-1)}' | xargs); tg=$(echo "$o" | awk -F'|' '/tg64/{print $(NF-1)}' | xargs)
		[ -n "$pp" ] && [ -n "$tg" ] && r PASS ai llama "$(basename "$M"): prompt $pp tok/s, text $tg tok/s" || r FAIL ai llama "no result"
	fi
fi

echo "SUMMARY: $NP PASS, $NW WARN, $NF FAIL (log $LOG)"
{ printf '{"time":"%s","mode":"%s","pass":%d,"warn":%d,"fail":%d,"checks":[' "$(date -Iseconds)" $MODE $NP $NW $NF
  (IFS=,; printf '%s' "${JSON[*]}"); printf ']}\n'; } > "$OUT/last.json"
exit $NF
