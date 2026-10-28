#!/usr/bin/env python3
"""Build the window test DTB from a BASE j516s dtb (the one inside the active boot.bin), not from live source.
usage: make-window-dtb.py <base.dtb> <out.dtb> <dtc> [--no-sep] [--camera] [--sensor] [--sensor-irq]
  default: add the SEP nodes and the sep alias; --camera sets apple,temporal-filter = 1 in the ISP node.
  --sensor (stage 3a): give the Mesa fingerprint node its power line (NUB GPIO 33 from the J516S ADT function-mesa_pwr),
           chip-select timing and the calibration firmware name. SPI controller and node stay disabled: the driver enables
           them at the first open of /dev/sep-bio. SPI mode (spi-cpha, copied from t8122) and the missing pin mux are UNVERIFIED.
  --sensor-irq (needs --sensor): also give the sensor node its data-ready interrupt, AP GPIO 200 (J516S ADT /arm-io/spi2/mesa
           interrupts = <0xc8 3>, parent the AP GPIO controller), rising edge. The driver then uses the SPI core's irq for interrupt
           capture instead of the SPI polling fallback. The edge and the pin are from the ADT; that the line idles low is unverified.
Decompiles, inserts the SEP nodes, spi2 and the sep alias, recompiles.
Phandles for aic, clk_200m, ps_spi2 are looked up from existing nodes."""
import re, subprocess, sys
args = [a for a in sys.argv[1:] if not a.startswith("--")]
flags = {a for a in sys.argv[1:] if a.startswith("--")}
src, out, dtc = args[:3]
want_sep = "--no-sep" not in flags
want_cam = "--camera" in flags
want_sensor = "--sensor" in flags or "--sensor-irq" in flags
want_irq = "--sensor-irq" in flags
MESA_PWR_PIN = 33           # ADT /arm-io/spi2/mesa function-mesa_pwr = <nub-gpio "GPIO" 0x21 ...>
MESA_FIRMWARE = "apple/mesacal-j516s.bin"
MESA_DRDY_PIN = 200         # ADT /arm-io/spi2/mesa interrupts = <0xc8 3>, interrupt-parent the AP GPIO controller
txt = subprocess.run([dtc, "-I", "dtb", "-O", "dts", src], capture_output=True, text=True).stdout

def node_block(txt, header_re):
    m = re.search(r"^(\t+)(?:[\w-]+: )?(" + header_re + r") \{\n", txt, re.M)
    if not m: raise SystemExit("node not found: " + header_re)
    ind = m.group(1)
    end = txt.index("\n" + ind + "};\n", m.end()) + len("\n" + ind + "};\n")
    return txt[m.start():end]

def prop(block, name):
    m = re.search(r"^\s*" + re.escape(name) + r" = <(0x[0-9a-f]+)>;", block, re.M)
    if not m: raise SystemExit("prop not found: " + name)
    return m.group(1)

spi1 = node_block(txt, r"spi@289104000")
aic = prop(spi1, "interrupt-parent")
clk = prop(spi1, "clocks")
# fresh phandles above the current maximum
mx = max(int(x, 16) for x in re.findall(r"phandle = <(0x[0-9a-f]+)>;", txt))
p_dart, p_mbox, p_sep, p_ps2 = (hex(mx + i) for i in (1, 2, 3, 4))
sensor_props = ""
if want_sensor:
    nub = node_block(txt, r"pinctrl@3641f0000")
    nub_ph, npins = prop(nub, "phandle"), int(prop(nub, "apple,npins"), 16)
    if MESA_PWR_PIN >= npins: raise SystemExit("mesa power pin %d is outside the NUB pinctrl (%d pins)" % (MESA_PWR_PIN, npins))
    sensor_props = (f"\t\t\t\tenable-gpios = <{nub_ph} {hex(MESA_PWR_PIN)} 0x00>;\n"
                    "\t\t\t\tspi-cs-setup-delay-ns = <0x14>;\n\t\t\t\tspi-cs-hold-delay-ns = <0x14>;\n"
                    f'\t\t\t\tfirmware-name = "{MESA_FIRMWARE}";\n')
if want_irq:
    ap = node_block(txt, r"pinctrl@347100000")
    ap_ph, ap_npins = prop(ap, "phandle"), int(prop(ap, "apple,npins"), 16)
    if MESA_DRDY_PIN >= ap_npins: raise SystemExit("data-ready pin %d is outside the AP pinctrl (%d pins)" % (MESA_DRDY_PIN, ap_npins))
    if "interrupt-controller;" not in ap: raise SystemExit("AP pinctrl is not an interrupt controller")
    # 1 = IRQ_TYPE_EDGE_RISING: the line idles low and the data-ready assert is the rising edge
    sensor_props += f"\t\t\t\tinterrupt-parent = <{ap_ph}>;\n\t\t\t\tinterrupts = <{hex(MESA_DRDY_PIN)} 0x01>;\n"
ps2_block = node_block(txt, r"power-controller@270")
if "phandle = <" in ps2_block:
    ps2 = prop(ps2_block, "phandle")
else:
    # ps_spi2 is unreferenced in the installed tree, so dtc gave it no phandle: add one.
    ps2 = p_ps2
    hdr_end = ps2_block.index("{\n") + 2
    ind = re.match(r"\t+", ps2_block).group(0) + "\t"
    txt = txt.replace(ps2_block, ps2_block[:hdr_end] + ind + f"phandle = <{ps2}>;\n" + ps2_block[hdr_end:], 1)

nodes = f"""
\t\tiommu@29cac0000 {{
\t\t\tcompatible = "apple,t6030-dart", "apple,t8110-dart";
\t\t\treg = <0x02 0x9cac0000 0x00 0x4000>;
\t\t\tinterrupt-parent = <{aic}>;
\t\t\tinterrupts = <0x00 0x174 0x04>;
\t\t\t#iommu-cells = <0x01>;
\t\t\tapple,dma-range = <0x100 0x4000 0x00 0xffff0000>;
\t\t\tapple,dma-offset = <0x00 0x00>;
\t\t\tstatus = "disabled";
\t\t\tphandle = <{p_dart}>;
\t\t}};

\t\tsep@29e400000 {{
\t\t\tcompatible = "apple,sep";
\t\t\treg = <0x02 0x9e400000 0x00 0x6c000>;
\t\t\tmboxes = <{p_mbox}>;
\t\t\tmbox-names = "mbox";
\t\t\tiommus = <{p_dart} 0x00>;
\t\t\tstatus = "disabled";
\t\t\tphandle = <{p_sep}>;
\t\t}};

\t\tmbox@29e408000 {{
\t\t\tcompatible = "apple,t6030-asc-mailbox", "apple,asc-mailbox-v4";
\t\t\treg = <0x02 0x9e408000 0x00 0x4000>;
\t\t\tinterrupt-parent = <{aic}>;
\t\t\tinterrupts = <0x00 0x16e 0x04 0x00 0x16f 0x04 0x00 0x170 0x04 0x00 0x171 0x04>;
\t\t\tinterrupt-names = "send-empty", "send-not-empty", "recv-empty", "recv-not-empty";
\t\t\t#mbox-cells = <0x00>;
\t\t\tphandle = <{p_mbox}>;
\t\t}};

\t\tspi@289108000 {{
\t\t\tcompatible = "apple,t6030-spi", "apple,t8103-spi";
\t\t\treg = <0x02 0x89108000 0x00 0x4000>;
\t\t\tinterrupt-parent = <{aic}>;
\t\t\tinterrupts = <0x00 0x36c 0x04>;
\t\t\t#address-cells = <0x01>;
\t\t\t#size-cells = <0x00>;
\t\t\tclocks = <{clk}>;
\t\t\tpower-domains = <{ps2}>;
\t\t\tstatus = "disabled";

\t\t\tfingerprint@0 {{
\t\t\t\tcompatible = "apple,mesa-fingerprint";
\t\t\t\treg = <0x00>;
\t\t\t\tspi-max-frequency = <0x7a1200>;
\t\t\t\tspi-cpha;
{sensor_props}\t\t\t\tstatus = "disabled";
\t\t\t}};
\t\t}};
"""
if want_sep:
    m = re.search(r"^\tsoc \{\n", txt, re.M)
    end = txt.index("\n\t};\n", m.end())
    txt = txt[:end + 1] + nodes.lstrip("\n") + txt[end + 1:]
    m = re.search(r"^\taliases \{\n", txt, re.M)
    txt = txt[:m.end()] + '\t\tsep = "/soc/sep@29e400000";\n' + txt[m.end():]
if want_cam:
    blk = node_block(txt, r"isp@2c8000000")
    if "apple,temporal-filter = <0x00>;" not in blk:
        raise SystemExit("isp node has no apple,temporal-filter = <0x00>: refusing to guess")
    txt = txt.replace(blk, blk.replace("apple,temporal-filter = <0x00>;", "apple,temporal-filter = <0x01>;", 1), 1)
open(out + ".dts", "w").write(txt)
r = subprocess.run([dtc, "-I", "dts", "-O", "dtb", "-o", out, out + ".dts"], capture_output=True, text=True)
print("dtc rc", r.returncode); print(r.stderr[-600:])
