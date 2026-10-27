#!/usr/bin/env bash
# Clean virtual camera for the M3 (apple-isp) without a kernel module and without root.
# Reads the real camera, denoises and corrects the colour with ffmpeg, and publishes the result as a
# PipeWire video source ("M3-Clean-Camera"). Apps that use PipeWire cameras (Firefox, Chromium with
# the PipeWire camera flag, GNOME and KDE camera apps) can pick it. Runs in the foreground; Ctrl-C stops it.
# Only one program can read the real camera at a time, so close other camera apps first.
# Needs: ffmpeg, gst-launch-1.0 with pipewire-gstreamer (pipewiresink). Costs about 1.5 CPU cores (hqdn3d).
#
# Usage: tools/camera-clean.sh [--size WxH] [--denoise hqdn3d|nlmeans|none] [--wb none|fixed|gray] [--name NAME]
#   --size     capture size, default 1280x720 (the camera offers 1920x1080, 1920x1440, 1280x960, 1280x720, 640x480)
#   --denoise  hqdn3d (default, cheap), nlmeans (better, about 2.6 cores) or none
#   --wb       none; fixed (gentle warm-to-neutral gains, stable, default); gray (grayworld: strong, follows the
#              scene, may tint a scene that is mostly one colour and may flicker)
set -eu
SIZE=1280x720; DEN=hqdn3d; WB=fixed; NAME=M3-Clean-Camera; FPS=30
while [ $# -gt 0 ]; do
	case "$1" in
	--size) SIZE="$2"; shift ;;
	--denoise) DEN="$2"; shift ;;
	--wb) WB="$2"; shift ;;
	--name) NAME="$2"; shift ;;
	-h|--help) sed -n 2,13p "$0"; exit 0 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
W=${SIZE%x*}; H=${SIZE#*x}

DEV=""
for v in /sys/class/video4linux/video*; do
	[ "$(cat "$v/name" 2>/dev/null)" = apple-isp ] && DEV="/dev/$(basename "$v")"
done
[ -n "$DEV" ] || { echo "no apple-isp video node" >&2; exit 1; }
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

case "$DEN" in
hqdn3d) VF="hqdn3d=4:3:8:6" ;;
nlmeans) VF="nlmeans=s=3:p=3:r=7" ;;
none) VF="" ;;
*) echo "bad --denoise" >&2; exit 2 ;;
esac
case "$WB" in
fixed) WBF="colorchannelmixer=rr=0.96:bb=1.10" ;;
gray) WBF="grayworld" ;;
none) WBF="" ;;
*) echo "bad --wb" >&2; exit 2 ;;
esac
CHAIN="$VF"
[ -n "$WBF" ] && CHAIN="${CHAIN:+$CHAIN,}$WBF"
CHAIN="${CHAIN:+$CHAIN,}format=yuyv422"

echo "camera-clean: $DEV -> PipeWire source '$NAME' ($SIZE, denoise $DEN, wb $WB). Ctrl-C to stop."
NODE="$(echo "$NAME" | tr 'A-Z ' 'a-z-')"
ffmpeg -nostdin -hide_banner -loglevel error -f v4l2 -video_size "$SIZE" -framerate "$FPS" -i "$DEV" -vf "$CHAIN" -f rawvideo - |
	gst-launch-1.0 -q fdsrc ! videoparse format=yuy2 width="$W" height="$H" framerate="$FPS"/1 ! queue ! \
		pipewiresink mode=provide \
		stream-properties="properties,media.class=Video/Source,media.role=Camera,node.name=$NODE,node.description=$NAME"
