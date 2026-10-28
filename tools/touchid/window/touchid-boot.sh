#!/usr/bin/env bash
# Touch ID + camera filter window, part 1 (before the reboot).
# Usage: touchid-boot.sh [--dry] [--camera] [--sensor] [--sensor-irq] [--probe]   (run as the user, NOT with sudo)
#   --sensor-irq  implies --sensor: also adds the sensor data-ready interrupt (AP GPIO 200, rising edge, from the ADT) to the sensor
#             node, so the driver uses interrupt capture instead of SPI polling (2 more lines in the DTB diff).
#   --probe   stage 3a+: implies --sensor (same DTB as 3a). The check script then loads the 3a+ module (apple-sep-3a.ko) with sensor_probe=1,
#             which reads only the sensor status over SPI (all four SPI modes if it stays silent). No keybag, no xART write.
#   --sensor  stage 3a: add the Mesa sensor power line (NUB GPIO 33), CS timing and calibration file name to the SPI2 sensor node
#             (4 added lines, nothing removed; the SPI bus and the node stay disabled, the driver enables them at the first /dev/sep-bio open).
#   --camera  also set apple,temporal-filter = 1. DO NOT USE: on 2026-10-27 this hung the ISP firmware (no frames, stop commands time out).
#   --dry  read-only: A0 checks, builds the test DTB, composes the expected boot.bin.sep under touchid/dry/.
#          Writes nothing to the ESP, installs nothing, changes nothing outside ~/window/touchid.
#   (no flag) builds boot.bin.sep, proves it differs from the base boot.bin only in the J516S dtb,
#          switches boot.bin to it, and arms a self-removing unit that puts the base boot.bin back
#          on the first boot that uses it. A plain reboot afterwards is therefore the test boot,
#          and the reboot after that is a normal boot again.
# Needs sudo -n. Never reboots.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/touchid"
DRY=0; CAMFLAG=""; SENSFLAG=""; PROBEFLAG=0; IRQFLAG=0
for a in "$@"; do case "$a" in --probe) PROBEFLAG=1; SENSFLAG="--sensor";; --dry) DRY=1;; --camera) CAMFLAG="--camera";; --sensor) SENSFLAG="--sensor";; --sensor-irq) SENSFLAG="--sensor --sensor-irq"; IRQFLAG=1;; *) echo "unknown option $a" >&2; exit 2;; esac; done
[ "$(id -u)" != 0 ] || { echo "[touchid-boot] STOP: run as the user, not with sudo (the script calls sudo -n itself)" >&2; exit 1; }
UHOME="/home/${SUDO_USER:-$USER}"
ESP=/boot/efi/m1n1
KREL=7.2.11-m3gpu+
M1N1=/usr/local/lib/m3gpu/m1n1-aca1258.bin
M1N1_SHA=3118c16f20ee32dba8c8eee14e00fd37c31ab6ab200d12c7cad6c1e60500a710
OPTS=(chosen.asahi,t6030-gpu=1 chosen.asahi,t6030-dcp=1 chosen.asahi,t6030-dcpext=1)
say() { echo "[touchid-boot] $*"; }
die() { echo "[touchid-boot] STOP: $*" >&2; exit 1; }
rt() { sudo -n "$@"; }
# diff exits 1 when files differ; with pipefail that would fail every pipeline below.
dd_() { diff "$W/work/base.dts" "$W/work/merged.dts" || true; }

sudo -n true 2>/dev/null || die "sudo -n does not work (the sudo window is closed)"
[ "$(sha256sum "$M1N1" | cut -d' ' -f1)" = "$M1N1_SHA" ] || die "m1n1 file hash differs from the pinned one"
[ "$(uname -r)" = "$KREL" ] || die "running kernel is $(uname -r), expected $KREL"
mkdir -p "$W/work" "$W/dry" "$W/logs"

# ---- A0: which boot.bin is active, and is it a known one?
cur=$(rt sha256sum $ESP/boot.bin | cut -d' ' -f1)
stagee=$(rt sha256sum $ESP/boot.bin.stageE | cut -d' ' -f1)
rt test -f $ESP/boot.bin.stock || die "boot.bin.stock is missing (use-bootbin.sh would refuse too)"
BASE=""
if [ "$cur" = "$stagee" ]; then
	BASE=stageE; BASE_DIR=/boot/dtb-$KREL
	[ "$(sha256sum $BASE_DIR/apple/t6030-j516s.dtb | cut -c1-8)" = "18baac96" ] || die "installed J516S dtb hash is not the known one"
elif rt test -f $ESP/boot.bin.ane && [ "$cur" = "$(rt sha256sum $ESP/boot.bin.ane | cut -d' ' -f1)" ]; then
	BASE=ane; BASE_DIR="$HOME/ane-stage2/dtbs-ane"
	[ -f "$BASE_DIR/apple/t6030-j516s.dtb" ] || die "boot.bin is the ANE file but $BASE_DIR/apple/t6030-j516s.dtb is missing"
else
	die "boot.bin ($cur) is neither stageE nor the ANE file. Another window changed it. Ask the coordinator."
fi
rt test -e /etc/systemd/system/ane-window-restore.service && die "the Neural Engine window is armed and has not booted yet (ane-window-restore.service exists). Finish it first."
rt test -e /etc/systemd/system/m3-touchid-restore.service && die "a Touch ID restore unit already exists. Run touchid-disarm.sh first."
say "A0 PASS: boot.bin is $BASE ($cur)"
BASE_DTB="$BASE_DIR/apple/t6030-j516s.dtb"

# ---- A4 (only when the base is stageE: the check script requires stageE)
if [ "$BASE" = stageE ] && [ $DRY = 0 ]; then
	out=$("$UHOME/m3gpu/scripts/pre-reboot-check.sh" 2>&1 || true)
	echo "$out" | grep -q "^PRE_REBOOT_OK" || { echo "$out" | tail -n 15; die "pre-reboot-check did not print PRE_REBOOT_OK"; }
	say "pre-reboot-check: PRE_REBOOT_OK"
fi

# ---- A1: merged test DTB (SEP nodes + sep alias + temporal filter = 1)
rm -rf "$W/dtbs-sep" "$W/work/merged.dtb"; mkdir -p "$W/dtbs-sep/apple"
cp "$BASE_DIR"/apple/t6*.dtb "$BASE_DIR"/apple/t81*.dtb "$W/dtbs-sep/apple/"
python3 -I "$W/make-window-dtb.py" "$BASE_DTB" "$W/work/merged.dtb" "$W/dtc" $CAMFLAG $SENSFLAG >"$W/work/dtb-build.log" 2>&1 || { cat "$W/work/dtb-build.log"; die "DTB build failed"; }
cp "$W/work/merged.dtb" "$W/dtbs-sep/apple/t6030-j516s.dtb"
"$W/dtc" -I dtb -O dts "$BASE_DTB" 2>/dev/null > "$W/work/base.dts"
"$W/dtc" -I dtb -O dts "$W/work/merged.dtb" 2>/dev/null > "$W/work/merged.dts"
removed=$(dd_ | grep -c '^<' || true)
added=$(dd_ | grep -c '^>' || true)
if [ -n "$CAMFLAG" ]; then
	dd_ | grep '^<' | grep -vq 'apple,temporal-filter = <0x00>;' && die "DTB diff removes a line other than the temporal filter"
	[ "$removed" = 1 ] || die "DTB diff removed $removed lines, expected exactly 1"
	dd_ | grep -q 'apple,temporal-filter = <0x01>;' || die "temporal filter line missing"
else
	[ "$removed" = 0 ] || die "DTB diff removed $removed lines, expected 0 (SEP only)"
fi
if [ -n "$SENSFLAG" ]; then
	for pat in 'enable-gpios = <0x[0-9a-f]* 0x21 0x00>;' 'spi-cs-setup-delay-ns = <0x14>;' 'spi-cs-hold-delay-ns = <0x14>;' 'firmware-name = "apple/mesacal-j516s.bin";'; do
		dd_ | grep -q "$pat" || die "sensor line missing in the DTB diff: $pat"
	done
	nubph=$(awk '/pinctrl@3641f0000 \{/,/^\t\t\};/' "$W/work/merged.dts" | sed -n 's/.*[^-]phandle = <\(0x[0-9a-f]*\)>;.*/\1/p' | head -n1)
	[ -n "$nubph" ] && dd_ | grep -q "enable-gpios = <$nubph 0x21 0x00>;" || die "enable-gpios does not point at the NUB pinctrl (phandle '$nubph') pin 33"
	spiblk=$(awk '/spi@289108000 \{/,/^\t\t\};/' "$W/work/merged.dts")
	[ "$(echo "$spiblk" | grep -c 'status = "disabled"')" = 2 ] && ! echo "$spiblk" | grep -q 'status = "okay"' || die "SPI2 controller and sensor node must both stay disabled in the DTB"
	[ "$added" -ge 4 ] || die "sensor option added only $added lines"
	if [ "$IRQFLAG" = 1 ]; then
		apph=$(awk '/pinctrl@347100000 \{/,/^\t\t\};/' "$W/work/merged.dts" | sed -n 's/^\t\t\tphandle = <\(0x[0-9a-f]*\)>;.*/\1/p' | head -n1)
		[ -n "$apph" ] && dd_ | grep -q "interrupt-parent = <$apph>;" && dd_ | grep -q 'interrupts = <0xc8 0x01>;' || die "sensor data-ready interrupt missing or not on the AP pinctrl (phandle '$apph') pin 200"
		[ "$added" -ge 6 ] || die "sensor-irq option added only $added lines"
		say "A1 PASS: sensor data-ready interrupt is AP GPIO 200 (AP pinctrl phandle $apph), rising edge"
	fi
	say "A1 PASS: sensor block: power line is NUB GPIO 33 (phandle $nubph), SPI2 and the sensor node stay disabled, calibration name apple/mesacal-j516s.bin"
	say "NOTE: SPI mode (cpha) and the missing SPI pin mux are unverified; the calibration file must be installed before the test boot (touchid-calib.sh)"
fi
dd_ | grep -q 'compatible = "apple,sep";' || die "SEP node missing"
dd_ | grep -q 'sep = "/soc/sep@' || die "sep alias missing"
"$W/dtc" -I dtb -O dts "$W/work/merged.dtb" 2>/dev/null | awk '/mbox@29e408000 \{/,/^\t\t\};/' > "$W/work/mbox-node.txt"
grep -q 'apple,asc-mailbox-v4' "$W/work/mbox-node.txt" || die "SEP mailbox node missing"
grep -q 'status = "disabled"' "$W/work/mbox-node.txt" && die "SEP mailbox node is disabled: the driver's mailbox lookup would defer silently (this was the 2026-10-27 bug)"
say "A1 PASS: SEP mailbox node is enabled (SEP node and DART stay disabled; the driver enables them)"
say "A1 PASS: test DTB adds $added lines, removes $removed ${CAMFLAG:+(temporal-filter 0 -> 1)}${CAMFLAG:-(SEP nodes and alias${SENSFLAG:+, sensor power/firmware lines}; camera filter stays 0)}"
for f in "$W"/dtbs-sep/apple/*.dtb; do b=$(basename "$f"); [ "$b" = t6030-j516s.dtb ] && continue; cmp -s "$f" "$BASE_DIR/apple/$b" || die "other dtb differs from base: $b"; done
say "A1 PASS: every other dtb equals the base copy"

# ---- compose the expected boot.bin.sep: base boot.bin with ONLY the J516S dtb replaced
rt cat $ESP/boot.bin > "$W/work/base.bin"
python3 -I - "$W/work/base.bin" "$BASE_DTB" "$W/work/merged.dtb" "$W/work/expected.bin" <<'PY'
import sys
base, bdtb, ndtb, out = (open(p, "rb").read() if i < 3 else p for i, p in enumerate(sys.argv[1:]))
assert base.count(bdtb) == 1, "base J516S dtb not found exactly once in boot.bin (%d)" % base.count(bdtb)
i = base.index(bdtb)
open(out, "wb").write(base[:i] + ndtb + base[i + len(bdtb):])
print("composed: base %d bytes, new %d bytes, dtb at offset %d" % (len(base), len(base) - len(bdtb) + len(ndtb), i))
PY
exp_sha=$(sha256sum "$W/work/expected.bin" | cut -d' ' -f1)
say "expected boot.bin.sep sha256 $exp_sha"
if [ $DRY = 1 ]; then
	cp "$W/work/expected.bin" "$W/dry/expected-boot.bin.sep"
	say "DRY RUN done. Nothing was written to the ESP. Expected file: $W/dry/expected-boot.bin.sep"
	exit 0
fi

# ---- A2: build boot.bin.sep (new file; boot.bin untouched) and prove it equals the expected composition
rt "$UHOME/m3gpu/scripts/make-bootbin.sh" sep "$M1N1" "$W/dtbs-sep" "${OPTS[@]}" | tail -n 8
rt cat $ESP/boot.bin.sep > "$W/work/sep.bin"
[ "$(sha256sum "$W/work/sep.bin" | cut -d' ' -f1)" = "$exp_sha" ] || { rt rm -f $ESP/boot.bin.sep; die "boot.bin.sep differs from the expected composition. Removed it. boot.bin is untouched."; }
say "A2/A3 PASS: boot.bin.sep equals the base with only the J516S dtb replaced"

# ---- A5: switch boot.bin, then arm the restore
rt "$UHOME/m3gpu/scripts/use-bootbin.sh" sep | tail -n 3
[ "$(rt sha256sum $ESP/boot.bin | cut -d' ' -f1)" = "$exp_sha" ] || die "boot.bin hash after the switch is wrong. Run touchid-disarm.sh now."
rt install -m 0755 "$W/restore-bootbin.sh" /usr/local/sbin/m3-touchid-restore
printf 'BASE=%s\nSEP_SHA=%s\nBASE_SHA=%s\n' "$BASE" "$exp_sha" "$cur" | rt tee /usr/local/lib/m3gpu/touchid-restore.env >/dev/null
rt tee /etc/systemd/system/m3-touchid-restore.service >/dev/null <<'UNIT'
[Unit]
Description=Put the known boot.bin back after the Touch ID test boot (removes itself)
After=local-fs.target
ConditionPathExists=/usr/local/lib/m3gpu/touchid-restore.env

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/m3-touchid-restore

[Install]
WantedBy=multi-user.target
UNIT
rt systemctl daemon-reload
rt systemctl enable m3-touchid-restore.service >/dev/null 2>&1
printf 'BASE=%s\nSEP_SHA=%s\nBASE_SHA=%s\nCAM=%s\nSENSOR=%s\nPROBE=%s\nWHEN=%s\n' "$BASE" "$exp_sha" "$cur" "$([ -n "$CAMFLAG" ] && echo 1 || echo 0)" "$([ -n "$SENSFLAG" ] && echo 1 || echo 0)" "$PROBEFLAG" "$(date '+%F %T')" > "$W/last-run.env"
say "ARMED. boot.bin is now the Touch ID + camera test file. The next boot uses it and then puts $BASE back by itself."
say "Undo before the reboot: $HERE/touchid-disarm.sh"
say "After the boot run: $HERE/touchid-check.sh${SENSFLAG:+ (it opens /dev/sep-bio once: stage 3a)}"
