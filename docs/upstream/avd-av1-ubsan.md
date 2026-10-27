# Draft: UBSAN array-index-out-of-bounds in the Apple AVD AV1 decoder

Status: draft for the user's review. Nothing is posted. The log and source gaps are filled (2026-10-27).

## Summary

`apple_avd` (the stateless V4L2 decoder for the Apple video decoder) triggers UBSAN
`array-index-out-of-bounds` reports while it decodes AV1 on an M3 Pro. The decode finishes,
all frames come out, and the picture is correct. The warnings show two reads past the end of an array in
`drivers/media/platform/apple/avd/avd-av1.c`.

## Environment

- MacBook Pro 16-inch, M3 Pro (Mac15,7, J516S, `apple,t6030-avd`, `apple,t8122-avd` fallback).
- Fedora Asahi Remix 44, kernel `7.2.11-m3gpu+` (Asahi tree plus out-of-tree M3 GPU and display patches; none touch the media driver).
- Firmware: `apple/avd-fw-v4-t0.bin`, built from AsahiLinux/avd-fw commit `220b1e70c9d7dcccbf66d5194e372300aa3c5a32`.
- Userspace: GStreamer 1.28.8 (`v4l2slav1dec`).

## What the kernel logged

12 lines at the first AV1 decode (2026-10-26 23:36), two distinct reports:

- `UBSAN: array-index-out-of-bounds in drivers/media/platform/apple/avd/avd-av1.c:452:4`
- `UBSAN: array-index-out-of-bounds in drivers/media/platform/apple/avd/avd-av1.c:581:33`

Call trace of the first report (module offsets as logged):

```
is_valid_ref_frame.isra.0+0x124/0x140 [apple_avd]
avd_select_refs.isra.0+0x280/0x360 [apple_avd]
set_header+0x75c/0x2fd8 [apple_avd]
avd_av1_run+0x18c/0x300 [apple_avd]
avd_device_run+0x94/0x2e0 [apple_avd]
```

Full lines (kernel log, 2026-10-26 23:36:17), each followed by `index -1 is out of range for type '__u64 [8]'`:

- `avd-av1.c:452:4`
- `avd-av1.c:481:36`
- `avd-av1.c:581:33`
- `avd-av1.c:582:33`

The type `__u64 [8]` is `reference_frame_ts` in `struct v4l2_ctrl_av1_frame`. The index `-1` is a value of `ref_frame_idx[]`.

Source (the lines the reports point at):

```c
/* is_valid_ref_frame(), from line 445 */
struct avd_decoded_buffer *ref = avd_get_ref_buf(
	ctx, &dst->base.vb,
	frame->reference_frame_ts
		[frame->ref_frame_idx[ref_frame - V4L2_AV1_REF_LAST_FRAME]]);

/* around line 574 to 584 */
for (i = 0; i < 6; i++) {
	for (j = i + 1; j < 7; j++) {
		if (frame->reference_frame_ts[frame->ref_frame_idx[i]] ==
		    frame->reference_frame_ts[frame->ref_frame_idx[j]]) {
```

Reading: the code indexes `reference_frame_ts[]` with `ref_frame_idx[...]` without checking that the value is in 0..7. For frames that do not use references (key frames and intra-only frames) the userspace control carries -1 in unused `ref_frame_idx[]` entries, so the lookup reads `reference_frame_ts[-1]`, one element before the array. This is a reading of the code and the log, not a tested fix.

## How to reproduce

1. Make a 10 s 1080p30 AV1 clip: `ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10 -c:v libsvtav1 -preset 10 -crf 35 -f ivf av1.ivf`
2. Decode: `gst-launch-1.0 filesrc location=av1.ivf ! ivfparse ! av1parse ! v4l2slav1dec ! video/x-raw ! fakesink sync=false`
3. Read `journalctl -k`.

## What works

- 300 of 300 frames out. The picture matches a libdav1d decode in shape and content; only the shade differs in a GStreamer colour conversion step that was not isolated.
- H.264, HEVC and VP9 decode on the same boot with no UBSAN report.

## Impact

Reads past the end of an array in kernel code. UBSAN reports only; no crash or corrupt output was seen. A kernel built without UBSAN or with a different compiler may read other data. Please advise whether the reference-frame check in `is_valid_ref_frame` needs a bound on the index.

## Not known

- Whether M1 and M2 also report it. Only the M3 Pro was tested.
- Whether the AV1 streams from real-world encoders trigger the same path (only one synthetic SVT-AV1 clip was tested).
