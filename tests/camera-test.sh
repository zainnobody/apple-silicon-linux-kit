#!/usr/bin/env bash
# Camera test for the M3 built-in camera (apple-isp). Prints PASS or FAIL per check and one overall line.
# Read-only on the system: no sudo, no module load. It opens the camera for a few seconds (the LED should light).
# The scene must be still and lit the same way for a fair before and after comparison.
#
# Checks:
#   FRAMES  frame count of a 5 s capture (default pass: at least 20 frames, as in touchid-check.sh)
#   NOISE   temporal noise: mean luma of the frame-to-frame difference (same method and number as
#           the baseline in touchid-check.sh). Lower is better. With --compare: pass if not worse.
#   CAST    colour cast: distance of the mean chroma (U, V) from neutral 128, plus the R/G and B/G
#           ratios of the mean colour. Lower distance is better. With --compare: pass if not worse.
#   LED     cannot be read by software: prints a reminder for the person at the machine.
#
# Usage:
#   tests/camera-test.sh --save-baseline [FILE]    measure and save the numbers (default ~/.cache/camera-test/baseline)
#   tests/camera-test.sh --compare [FILE]          measure and compare with the saved numbers
#   Options: --seconds N (5)  --size WxH  --dyn-fps 0|1  --vf "ffmpeg filter chain"  --keep
#     --pw NODE reads a PipeWire video source by node name (for example the clean virtual camera
#     m3-clean-camera from tools/camera-clean.sh, which must already run) instead of /dev/video*.
#     --dyn-fps sets the V4L2 control "Exposure, Dynamic Framerate" (0x009a0903) while the capture runs.
#     --vf applies an ffmpeg filter chain before the measurement (to test a user-space denoise).
#     --keep keeps the last frame as ./camera-test-last.jpg (it may show a person or a room).
#   Env: MIN_FRAMES (20)  CAST_MAX (unset: no absolute limit; only --compare judges the cast)
# Exit code: 0 all PASS, 1 any FAIL.
set -u

SECS=5; SIZE=""; DYN=""; VF=""; KEEP=0; MODE=""; BASEFILE=""; PW=""
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/camera-test"
MIN_FRAMES="${MIN_FRAMES:-20}"
while [ $# -gt 0 ]; do
	case "$1" in
	--save-baseline) MODE=save; if [ "${2:-}" != "" ] && [ "${2#--}" = "$2" ]; then BASEFILE="$2"; shift; fi ;;
	--compare) MODE=compare; if [ "${2:-}" != "" ] && [ "${2#--}" = "$2" ]; then BASEFILE="$2"; shift; fi ;;
	--seconds) SECS="$2"; shift ;;
	--size) SIZE="$2"; shift ;;
	--dyn-fps) DYN="$2"; shift ;;
	--vf) VF="$2"; shift ;;
	--keep) KEEP=1 ;;
	--pw) PW="$2"; shift ;;
	-h|--help) sed -n 2,30p "$0"; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
BASEFILE="${BASEFILE:-$CACHE/baseline}"

FAILS=0
verdict() { # name PASS|FAIL detail
	printf '%-7s %-5s %s\n' "$1" "$2" "$3"
	[ "$2" = FAIL ] && FAILS=$((FAILS + 1))
	return 0
}

camera_dev() {
	local v
	for v in /sys/class/video4linux/video*; do
		[ "$(cat "$v/name" 2>/dev/null)" = apple-isp ] && { echo "/dev/$(basename "$v")"; return 0; }
	done
	return 1
}

# Set or read the dynamic framerate control, holding the device open for $3 seconds.
dyn_ctrl() { # dev value hold_seconds
	python3 - "$1" "$2" "$3" <<'EOF'
import fcntl, os, struct, sys, time
dev, val, hold = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
S_CTRL = 0xc008561c
G_CTRL = 0xc008561b
CID = 0x009a0903
fd = os.open(dev, os.O_RDWR)
b = bytearray(struct.pack("Ii", CID, val))
try:
    fcntl.ioctl(fd, S_CTRL, b)
    g = bytearray(struct.pack("Ii", CID, 0))
    fcntl.ioctl(fd, G_CTRL, g)
    print("dynfps_readback", struct.unpack("Ii", g)[1], flush=True)
except OSError as e:
    print("dynfps_error", e, flush=True)
time.sleep(hold)
EOF
}

W=$(mktemp -d /tmp/camera-test.XXXXXX)
trap 'rm -rf "$W"' EXIT
echo "camera-test $(date +%F\ %T) kernel $(uname -r)"

if [ -n "$PW" ]; then
	DEV="pipewire:$PW"
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
	if ! pw-dump 2>/dev/null | grep -q "\"node.name\": \"$PW\""; then verdict DEVICE FAIL "PipeWire source $PW not found (start tools/camera-clean.sh first)"; echo "RESULT FAIL"; exit 1; fi
	verdict DEVICE PASS "PipeWire source $PW"
	mkdir -p "$W/pw"
	timeout $((SECS + 40)) gst-launch-1.0 -q pipewiresrc target-object="$PW" num-buffers=$((SECS * 30)) ! videoconvert ! video/x-raw,format=I420 ! \
		jpegenc quality=95 ! multifilesink location="$W/pw/f%04d.jpg" >"$W/gst.txt" 2>&1
	RC=$?
	FRAMES=$(find "$W/pw" -name 'f*.jpg' | wc -l | tr -d ' ')
	ffmpeg -nostdin -hide_banner -loglevel error -framerate 30 -i "$W/pw/f%04d.jpg" -c:v copy -y "$W/cap.mkv" 2>/dev/null
else
DEV=$(camera_dev) || { verdict DEVICE FAIL "no apple-isp video node"; echo "RESULT FAIL"; exit 1; }
verdict DEVICE PASS "apple-isp at $DEV"

# Capture. The filter chain (if any) runs before the mjpeg encode, so the file holds what an app would see.
OUT=(-c:v mjpeg -q:v 3)
[ -n "$VF" ] && OUT=(-vf "$VF" "${OUT[@]}")
if [ -n "$DYN" ]; then
	dyn_ctrl "$DEV" "$DYN" $((SECS + 4)) >"$W/dyn.txt" 2>&1 &
	DYNPID=$!
	sleep 1
fi
LOG=$(timeout $((SECS + 40)) ffmpeg -nostdin -hide_banner -f v4l2 ${SIZE:+-video_size "$SIZE"} -i "$DEV" -t "$SECS" "${OUT[@]}" -y "$W/cap.mkv" 2>&1)
RC=$?
[ -n "$DYN" ] && { wait "$DYNPID" 2>/dev/null; echo "dyn-fps: $(tr '\n' ' ' <"$W/dyn.txt")"; }
FRAMES=$(echo "$LOG" | grep -o 'frame= *[0-9]*' | tail -n1 | grep -o '[0-9]*$'); FRAMES=${FRAMES:-0}
fi
FPS=$(awk -v f="$FRAMES" -v s="$SECS" 'BEGIN{printf "%.1f", f/s}')
if [ "$RC" -eq 0 ] && [ "$FRAMES" -ge "$MIN_FRAMES" ]; then
	verdict FRAMES PASS "frames=$FRAMES in ${SECS}s (${FPS} fps)${SIZE:+, size $SIZE}${VF:+, vf $VF}"
else
	verdict FRAMES FAIL "capture rc=$RC frames=$FRAMES (need $MIN_FRAMES)"
	echo "RESULT FAIL"; exit 1
fi

# Noise: same method as touchid-check.sh (mean luma of the frame-to-frame difference).
ffmpeg -nostdin -hide_banner -loglevel error -i "$W/cap.mkv" \
	-vf "format=gray,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=$W/n.txt" -f null - 2>/dev/null
NOISE=$(awk -F= '/YAVG/{s+=$2;n++} END{if(n) printf "%.3f", s/n; else printf "n/a"}' "$W/n.txt")

# Colour cast: mean U and V (neutral = 128) and mean colour ratios.
ffmpeg -nostdin -hide_banner -loglevel error -i "$W/cap.mkv" \
	-vf "signalstats,metadata=print:key=lavfi.signalstats.UAVG:file=$W/u.txt,metadata=print:key=lavfi.signalstats.VAVG:file=$W/v.txt" -f null - 2>/dev/null
UAVG=$(awk -F= '/UAVG/{s+=$2;n++} END{if(n) printf "%.2f", s/n}' "$W/u.txt")
VAVG=$(awk -F= '/VAVG/{s+=$2;n++} END{if(n) printf "%.2f", s/n}' "$W/v.txt")
RGB=$(ffmpeg -nostdin -hide_banner -loglevel error -i "$W/cap.mkv" -vf "scale=1:1:flags=area,format=rgb24" -f rawvideo - 2>/dev/null |
	od -An -v -tu1 -w3 | awk '{r+=$1;g+=$2;b+=$3;n++} END{if(n&&g>0) printf "%.3f %.3f", r/g, b/g}')
CAST=$(awk -v u="${UAVG:-128}" -v v="${VAVG:-128}" 'BEGIN{printf "%.2f", sqrt((u-128)^2+(v-128)^2)}')
RG=${RGB%% *}; BG=${RGB##* }

echo "numbers: noise=$NOISE cast=$CAST (U=$UAVG V=$VAVG) R/G=$RG B/G=$BG frames=$FRAMES fps=$FPS"

if [ "$NOISE" = "n/a" ]; then verdict NOISE FAIL "could not compute"; fi
if [ "$MODE" = save ]; then
	mkdir -p "$(dirname "$BASEFILE")"
	printf 'noise=%s\ncast=%s\nrg=%s\nbg=%s\nframes=%s\nkernel=%s\nwhen=%s\n' "$NOISE" "$CAST" "$RG" "$BG" "$FRAMES" "$(uname -r)" "$(date +%F\ %T)" >"$BASEFILE"
	verdict NOISE PASS "saved baseline noise=$NOISE (lower is better) to $BASEFILE"
	verdict CAST PASS "saved baseline cast=$CAST R/G=$RG B/G=$BG"
elif [ "$MODE" = compare ]; then
	if [ -f "$BASEFILE" ]; then
		BN=$(sed -n 's/^noise=//p' "$BASEFILE"); BC=$(sed -n 's/^cast=//p' "$BASEFILE")
		if awk -v a="$NOISE" -v b="$BN" 'BEGIN{exit !(a<=b)}'; then
			verdict NOISE PASS "noise $NOISE against baseline $BN (change $(awk -v a="$NOISE" -v b="$BN" 'BEGIN{printf "%+.1f%%", (a-b)/b*100}'))"
		else
			verdict NOISE FAIL "noise $NOISE is worse than baseline $BN"
		fi
		if awk -v a="$CAST" -v b="$BC" 'BEGIN{exit !(a<=b)}'; then
			verdict CAST PASS "cast $CAST against baseline $BC"
		else
			verdict CAST FAIL "cast $CAST is worse than baseline $BC"
		fi
	else
		verdict NOISE FAIL "no baseline file $BASEFILE (run --save-baseline first)"
	fi
else
	verdict NOISE PASS "noise=$NOISE (no baseline; lower is better)"
	if [ -n "${CAST_MAX:-}" ]; then
		if awk -v a="$CAST" -v b="$CAST_MAX" 'BEGIN{exit !(a<=b)}'; then verdict CAST PASS "cast $CAST <= $CAST_MAX"; else verdict CAST FAIL "cast $CAST > $CAST_MAX"; fi
	else
		verdict CAST PASS "cast=$CAST (no limit set; use --compare or CAST_MAX)"
	fi
fi

if [ "$KEEP" = 1 ]; then
	ffmpeg -nostdin -hide_banner -loglevel error -sseof -1 -i "$W/cap.mkv" -frames:v 1 -y ./camera-test-last.jpg 2>/dev/null && echo "kept ./camera-test-last.jpg (may show a person or a room)"
fi
echo "LED     ASK   a person at the machine must say whether the camera LED lit during the ${SECS}s capture"
if [ "$FAILS" -eq 0 ]; then echo "RESULT PASS"; exit 0; else echo "RESULT FAIL ($FAILS check(s))"; exit 1; fi
