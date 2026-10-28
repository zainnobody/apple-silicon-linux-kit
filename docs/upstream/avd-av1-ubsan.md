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

Cause: `ref_frame_idx[]` is `__s8`. A slot the frame does not use holds -1 (key frames and intra-only frames, and callers that mark a slot unused). The driver indexes `reference_frame_ts[]` with it directly at these places in `avd-av1.c` (line numbers of the tree above): 363 (`set_refs`), 452 (`is_valid_ref_frame`), 481 (`avd_select_refs`, `last_ref_idx`), 581 and 582 (`set_ref_hdr`, the pair comparison), plus 550, 828 and 1073 (these only see slots that were selected or a valid primary reference, so they were not reported, but they use the same pattern). The read at `[-1]` takes the 8 bytes before the array inside the control struct and uses them as a buffer timestamp. `avd_get_ref_buf()` returns the destination buffer for an unknown timestamp, so the visible result was normally right and only UBSAN noticed.

Proposed fix: `patches/avd-av1-ref-idx-bounds.patch` (in the kit repo). A new helper `avd_av1_ref_buf()` returns the destination buffer for a slot outside 0..7, the same value `avd_get_ref_buf()` already returns for an unknown timestamp, so decode output does not change. `set_ref_hdr()` skips slot pairs with an invalid index. 8 hunks, one file.

Status of the fix: the patched file compiles without warnings with the M3 kernel build flags (7.2.11-m3gpu+); the patch applies to the tree above. **It was not loaded or run**: loading a module needs root, and no root window was open. The 300-frame AV1 check with the patched module is still to do.

## How to reproduce

1. Make a 10 s 1080p30 AV1 clip: `ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10 -c:v libsvtav1 -preset 10 -crf 35 -f ivf av1.ivf`
2. Decode: `gst-launch-1.0 filesrc location=av1.ivf ! ivfparse ! av1parse ! v4l2slav1dec ! video/x-raw ! fakesink sync=false`
3. Read `journalctl -k`.

## What works

- 300 of 300 frames out. The picture matches a libdav1d decode in shape and content; only the shade differs in a GStreamer colour conversion step that was not isolated.
- H.264, HEVC and VP9 decode on the same boot with no UBSAN report.

## Impact

Reads past the end of an array in kernel code. UBSAN reports only; no crash or corrupt output was seen. A kernel built without UBSAN or with a different compiler may read other data. The patch above bounds every use of the index.

## Not known

- Whether M1 and M2 also report it. Only the M3 Pro was tested.
- Whether the AV1 streams from real-world encoders trigger the same path (only one synthetic SVT-AV1 clip was tested).
