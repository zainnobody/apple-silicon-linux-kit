#!/usr/bin/env python3
"""Build TEST-LOG.html: one local page with the overview, every document and every script.

Inputs (paths relative to the repository root):
  log/overview.html     overview: its <style>, its .wrap content and its <script>
  REPORTS               markdown documents, rendered in full
  CODE_DIRS             every file in these folders, shown as code; the summary is
                        the file's first comment line
Run: python3 -I log/build-log.py   (from anywhere; no third-party modules)
"""
import datetime
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "TEST-LOG.html")

# (id, title, path, one-line summary). Order is the reading order.
# A missing file is listed as missing on the page; ../TASKS.md exists only in
# the working session that created this repository.
REPORTS = [
    ("readme", "README", "README.md", "What this project is, how to build and install it, how to undo it."),
    ("machines", "Machine profiles", "machines/README.md", "Tested machines and how to add a machine."),
    ("tasks", "Task list", "../TASKS.md", "Open follow-ups and ideas (working session only)."),
    ("performance", "Performance and stability", "docs/performance.md", "Benchmarks, soak results and the comparison plan."),
    ("firmware", "GPU firmware investigation", "docs/gpu-firmware-investigation.md", "Why the GPU firmware was refused, the B1 chip revision, the pin and the stage F result."),
    ("upstream-draft", "Upstream report (posted as issue #20)", "docs/upstream-report-draft.md", "Draft issue text for SiliconForest about the cd05af6a hash."),
    ("install-plan", "Install plan and stage results", "docs/install-plan.md", "Boot chain, stages A to E, rollback from macOS, clean-up list."),
    ("build-status", "Build status", "docs/build-status.md", "Kernel, m1n1 and Mesa builds on the M3."),
    ("stack-review", "GPU stack review", "docs/gpu-stack-review.md", "Review of the SiliconForest kernel, m1n1 and Mesa, and the safe config."),
    ("status-report", "Asahi M3 Pro status report", "docs/asahi-m3-pro-status.md", "What Asahi supports on the M3 Pro, with dates and sources."),
    ("feasibility", "How to finish the missing parts", "docs/feasibility.md", "REA, project policies, community repos, private-build feasibility."),
    ("rea-plan", "REA for Apple plan", "docs/rea-plan.md", "Plan for a private reverse-engineering toolkit, GPU first."),
    ("install-findings", "Asahi install findings", "docs/asahi-install-findings.md", "Notes from the session that installed Fedora Asahi."),
    ("f-audio", "Feature: audio, camera and video", "docs/features/audio-camera-video.md", "Speakers, microphones, webcam, hardware video decode and encode."),
    ("f-bluetooth", "Feature: Bluetooth", "docs/features/bluetooth.md", "hci0 timeouts after resume and the recovery patch."),
    ("f-display", "Feature: display and HDMI", "docs/features/display-hdmi.md", "Built-in panel, 120 Hz, HDMI, USB-C display."),
    ("f-drivers", "Feature: missing drivers", "docs/features/missing-drivers.md", "Devices in the device tree with no bound driver."),
    ("f-ports", "Feature: ports, wireless and storage", "docs/features/ports-wireless-storage.md", "USB-C, SD card, Wi-Fi, Bluetooth scan, SSD, AirDrop."),
    ("f-sleep", "Feature: sleep, lid and battery", "docs/features/sleep-lid-battery.md", "Suspend, lid events, battery, power."),
    ("f-usb4", "Feature: USB-C and USB4 gap", "docs/features/usbc-usb4-gap.md", "Why USB-C displays fail and the USB4 module fix."),
    ("f-fans", "Feature: fans and heat", "docs/features/fans-heat.md", "Fan control unlock (Ftst), the fan curve service and its fail-safe."),
    ("f-airdrop", "Feature: AirDrop", "docs/features/airdrop.md", "OpenDrop-based AirDrop, the root step and the tests left."),
    ("f-video-encode", "Feature: video encode", "docs/features/video-encode.md", "Hardware video encoder (AVE) research."),
    ("f-touchid", "Feature: Touch ID", "docs/features/touchid.md", "Secure Enclave and fingerprint sensor: stages 1 to 3f and the results."),
    ("f-touchid-2", "Touch ID stage 2 plan", "docs/features/touchid-stage2-plan.md", "Test boot plan and window results."),
    ("f-touchid-3b", "Touch ID stage 3b plan", "docs/features/touchid-stage3b-plan.md", "Enrol plan, xART guard, alarm check, stop rules."),
    ("gpu-fault", "GPU fault 2026-10-26", "docs/gpu-fault-2026-10-26.md", "The KWin crash, the recovery race and the stage O fix."),
    ("memory", "Memory bandwidth and PMP", "docs/memory-pmp-findings.md", "The memory floor patch and what it changed."),
    ("whats-in", "What is in the repository", "docs/whats-in-the-repo.md", "Index of every driver, patch, tool and test, and where it is."),
]

CODE_DIRS = ["config.sh", "config.local.example.sh", "machines", "build", "install", "system", "patches", "tests", "log/build-log.py"]
CODE_EXT = (".sh", ".in", ".c", ".swift", ".py", ".patch", ".service")


def first_comment(text):
    """First sentence of the file's leading comment block."""
    parts = []
    for line in text.splitlines()[:15]:
        t = line.strip()
        if t.startswith("#!") or t.startswith("# shellcheck") or (not t and not parts):
            continue
        m = re.match(r'^(#|//|"""|\[Unit\])\s*(.*)$', t)
        if not m or not t:
            break
        if m.group(2):
            parts.append(m.group(2).rstrip('"').strip())
    joined = " ".join(parts)
    cut = re.search(r"^(.+?[.])(\s|$)", joined)
    return (cut.group(1) if cut else joined)[:220]


def code_files():
    out = []
    for entry in CODE_DIRS:
        full = os.path.join(ROOT, entry)
        if os.path.isfile(full):
            out.append(entry)
            continue
        for name in sorted(os.listdir(full)):
            if name.endswith(CODE_EXT) and os.path.isfile(os.path.join(full, name)):
                out.append(os.path.join(entry, name))
    result = []
    for rel in out:
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        summary = first_comment(text) or ("Patch: " + rel if rel.endswith(".patch") else "")
        result.append((rel, summary))
    return result


SCRIPTS = code_files()


def path_of(p):
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


# ---------- Minimal markdown to HTML (headings, lists, tables, code, quotes, inline) ----------

def inline(text):
    parts = re.split(r"(`[^`]+`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            out.append("<code>" + html.escape(part[1:-1]) + "</code>")
            continue
        s = html.escape(part, quote=False)
        s = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
                   lambda m: '<a href="%s" target="_blank" rel="noopener">%s</a>' % (html.escape(m.group(2)), m.group(1)), s)
        s = re.sub(r"(?<![\"'>=])(https?://[^\s<)]+)", r'<a href="\1" target="_blank" rel="noopener">\1</a>', s)
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"(?<![*\w])\*([^*\s][^*]*)\*(?!\w)", r"<em>\1</em>", s)
        out.append(s)
    return "".join(out)


def slug(prefix, text, used):
    base = prefix + "-" + (re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "s")
    s, n = base, 2
    while s in used:
        s, n = "%s-%d" % (base, n), n + 1
    used.add(s)
    return s


def md_to_html(md, prefix):
    lines = md.replace("\r\n", "\n").split("\n")
    out, used, toc = [], set(), []
    i, n = 0, len(lines)
    list_stack = []  # (indent, tag)

    def close_lists(to_indent=-1):
        while list_stack and list_stack[-1][0] > to_indent:
            out.append("</li></%s>" % list_stack.pop()[1])

    while i < n:
        line = lines[i]
        if line.strip().startswith("```"):
            close_lists()
            lang = line.strip()[3:].strip()
            buf = []
            i += 1
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            out.append('<pre class="code"%s><code>%s</code></pre>' % (
                ' data-lang="%s"' % html.escape(lang) if lang else "", html.escape("\n".join(buf))))
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            close_lists()
            level = min(len(m.group(1)) + 1, 6)
            text = m.group(2).strip()
            hid = slug(prefix, text, used)
            if level <= 3:
                toc.append((level, hid, text))
            out.append('<h%d id="%s">%s</h%d>' % (level, hid, inline(text), level))
            i += 1
            continue
        if re.match(r"^\s*\|.*\|\s*$", line) and i + 1 < n and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            close_lists()
            def cells(row):
                return [c.strip() for c in row.strip().strip("|").split("|")]
            head = cells(line)
            i += 2
            rows = []
            while i < n and re.match(r"^\s*\|.*\|\s*$", lines[i]):
                rows.append(cells(lines[i]))
                i += 1
            t = ['<div class="table-wrap"><table><thead><tr>']
            t += ["<th>%s</th>" % inline(c) for c in head]
            t.append("</tr></thead><tbody>")
            for r in rows:
                t.append("<tr>" + "".join("<td>%s</td>" % inline(c) for c in r) + "</tr>")
            t.append("</tbody></table></div>")
            out.append("".join(t))
            continue
        m = re.match(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$", line)
        if m:
            indent = len(m.group(1).replace("\t", "    "))
            tag = "ol" if m.group(2)[0].isdigit() else "ul"
            item = m.group(3)
            cb = re.match(r"^\[([ xX])\]\s+(.*)$", item)
            if cb:
                item = ('<span class="box">%s</span> ' % ("done" if cb.group(1) != " " else "open")) + inline(cb.group(2))
            else:
                item = inline(item)
            if list_stack and indent > list_stack[-1][0]:
                out.append("<%s>" % tag)
                list_stack.append((indent, tag))
            else:
                close_lists(indent)
                if list_stack and list_stack[-1][0] == indent:
                    out.append("</li>")
                else:
                    out.append("<%s>" % tag)
                    list_stack.append((indent, tag))
            out.append("<li>" + item)
            i += 1
            continue
        if list_stack and line.strip() and line.startswith(" "):
            out.append(" " + inline(line.strip()))
            i += 1
            continue
        if line.strip().startswith(">"):
            close_lists()
            buf = []
            while i < n and lines[i].strip().startswith(">"):
                buf.append(lines[i].strip()[1:].strip())
                i += 1
            out.append("<blockquote>%s</blockquote>" % inline(" ".join(buf)))
            continue
        if re.match(r"^\s*(-{3,}|\*{3,})\s*$", line):
            close_lists()
            out.append("<hr>")
            i += 1
            continue
        if not line.strip():
            close_lists()
            i += 1
            continue
        close_lists()
        buf = [line.strip()]
        i += 1
        while i < n and lines[i].strip() and not re.match(r"^(#{1,6}\s|\s*([-*+]|\d+[.)])\s|\s*\||\s*```|\s*>)", lines[i]):
            buf.append(lines[i].strip())
            i += 1
        out.append("<p>%s</p>" % inline(" ".join(buf)))
    close_lists()
    return "\n".join(out), toc


# ---------- Page assembly ----------

def main():
    tracker = open(path_of("log/overview.html"), encoding="utf-8").read()
    style = re.search(r"<style>(.*?)</style>", tracker, re.S).group(1)
    script = re.search(r"<script>(.*?)</script>", tracker, re.S).group(1)
    wrap = re.search(r'<div class="wrap">(.*)</div>\s*<script>', tracker, re.S).group(1)
    # The overview's short file list is replaced by the full reports below.
    wrap = re.sub(r'<section aria-labelledby="docs">.*?</section>', "", wrap, flags=re.S)
    footer = re.search(r"<footer>.*?</footer>", wrap, re.S)
    footer_html = footer.group(0) if footer else ""
    wrap = wrap.replace(footer_html, "")

    missing = []
    doc_index, doc_bodies = [], []
    for rid, title, p, summary in REPORTS:
        fp = path_of(p)
        if not os.path.exists(fp):
            missing.append(p)
            continue
        body, toc = md_to_html(open(fp, encoding="utf-8").read(), rid)
        mtime = datetime.datetime.fromtimestamp(os.path.getmtime(fp)).strftime("%Y-%m-%d %H:%M")
        doc_index.append('<li><a href="#doc-%s">%s</a><small>%s</small></li>' % (rid, html.escape(title), html.escape(summary)))
        toc_html = ""
        sub = [t for t in toc if t[0] == 3]
        if len(sub) > 2:
            toc_html = '<nav class="doc-toc" aria-label="Sections"><ul>%s</ul></nav>' % "".join(
                '<li><a href="#%s">%s</a></li>' % (h, inline(t)) for _, h, t in sub)
        doc_bodies.append(
            '<article class="doc-full" id="doc-%s"><header class="doc-head"><span class="kicker">%s, changed %s</span>'
            '<a class="top" href="#reports">Back to the list</a></header>%s<div class="md">%s</div></article>'
            % (rid, html.escape(os.path.basename(p)), mtime, toc_html, body))

    script_index, script_bodies = [], []
    for p, summary in SCRIPTS:
        fp = path_of(p)
        if not os.path.exists(fp):
            missing.append(p)
            continue
        sid = re.sub(r"[^a-z0-9]+", "-", p.lower())
        script_index.append('<li><a href="#src-%s"><code>%s</code></a><small>%s</small></li>' % (sid, html.escape(p), html.escape(summary)))
        script_bodies.append(
            '<details class="src" id="src-%s"><summary><code>%s</code> <span>%s</span></summary><pre class="code"><code>%s</code></pre></details>'
            % (sid, html.escape(p), html.escape(summary), html.escape(open(fp, encoding="utf-8").read())))

    built = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    extra_css = """
.topnav { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 5; background: var(--bg); border-bottom: 1px solid var(--line);
  padding-block: 10px; display: flex; flex-wrap: wrap; gap: 6px 18px; font-size: 0.9rem; }
body::before { content: ""; position: fixed; inset: 0 0 auto; height: env(safe-area-inset-top, 0px); z-index: 10; background: var(--bg); }
.topnav a { color: var(--ink); text-decoration: none; font-weight: 500; padding: 4px 0; }
.topnav a:hover { color: var(--accent); }
.index { list-style: none; margin: 0; padding: 0; display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 12px 20px; }
.index li { display: grid; gap: 2px; border-top: 2px solid var(--line); padding-top: 8px; min-width: 0; }
.index small { color: var(--muted); }
.index code { overflow-wrap: anywhere; }
.doc-full { border-top: 3px solid var(--ink); padding-top: 14px; display: grid; gap: 12px; min-width: 0; scroll-margin-top: 60px; }
.doc-head { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 8px; }
.doc-head .top { font-size: 0.85rem; }
.doc-toc ul { margin: 0; padding-left: 18px; columns: 2 220px; font-size: 0.88rem; }
.md { display: grid; gap: 12px; min-width: 0; }
.md h2 { font-size: 1.5rem; margin-top: 4px; }
.md h3 { font-size: 1.2rem; margin-top: 10px; scroll-margin-top: 60px; }
.md h4, .md h5, .md h6 { font-size: 1rem; margin-top: 6px; }
.md p, .md li { max-width: 72ch; overflow-wrap: anywhere; }
.md ul, .md ol { margin: 0; padding-left: 22px; display: grid; gap: 4px; }
.md blockquote { margin: 0; padding: 8px 14px; border-left: 3px solid var(--line); color: var(--muted); }
.md hr { border: 0; border-top: 1px solid var(--line); width: 100%; }
.md td { overflow-wrap: anywhere; min-width: 90px; }
.box { font-size: 0.72rem; font-weight: 600; padding: 1px 6px; border-radius: 4px; background: var(--wait-bg); color: var(--wait); }
pre.code { margin: 0; background: var(--code-bg); border-radius: 6px; padding: 12px; overflow-x: auto; font-family: var(--f-mono); font-size: 0.8rem; line-height: 1.5; }
.src { border-top: 1px solid var(--line); padding-block: 8px; scroll-margin-top: 60px; }
.src summary { cursor: pointer; display: flex; flex-wrap: wrap; gap: 4px 10px; align-items: baseline; padding-block: 6px; }
.src summary span { color: var(--muted); font-size: 0.88rem; }
.src[open] summary { margin-bottom: 8px; }
.missing { color: var(--fail); }
"""
    missing_html = ""
    if missing:
        missing_html = '<p class="missing">Not found when this page was built: %s</p>' % ", ".join(html.escape(m) for m in missing)

    page = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>agx-linux-kit Test Log</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Sans+Condensed:wght@500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>%(style)s
%(extra)s</style>
</head>
<body>
<div class="wrap">
<nav class="topnav" aria-label="Page">
  <a href="#now">Now</a><a href="#gpu">GPU</a><a href="#chain">Boot chain</a><a href="#stages">Stages</a><a href="#features">Hardware</a>
  <a href="#left">What is left</a><a href="#rollback">Rollback</a><a href="#reports">Reports</a><a href="#scripts">Scripts</a>
</nav>
%(wrap)s
<section aria-labelledby="reports">
  <h2 id="reports">Reports</h2>
  <p>Every report from this project, in full. Each one is rendered from its markdown file when this page is built.</p>
  %(missing)s
  <ul class="index">%(doc_index)s</ul>
</section>
%(doc_bodies)s
<section aria-labelledby="scripts">
  <h2 id="scripts">Scripts and patches</h2>
  <p>The exact files used on the M3. Open one to read it.</p>
  <ul class="index">%(script_index)s</ul>
  <div>%(script_bodies)s</div>
</section>
%(footer)s
<p class="kicker">Built %(built)s by log/build-log.py from the files in this repository.</p>
</div>
<script>%(script)s
document.querySelectorAll('a[href^="#src-"]').forEach(function (a) {
  a.addEventListener('click', function () {
    var d = document.getElementById(a.getAttribute('href').slice(1));
    if (d) d.open = true;
  });
});
</script>
</body>
</html>
""" % {
        "style": style, "extra": extra_css, "wrap": wrap, "missing": missing_html,
        "doc_index": "".join(doc_index), "doc_bodies": "\n".join(doc_bodies),
        "script_index": "".join(script_index), "script_bodies": "".join(script_bodies),
        "footer": footer_html, "built": built, "script": script,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(page)
    print("wrote %s (%d bytes, %d reports, %d scripts, missing: %s)" % (OUT, len(page.encode()), len(doc_bodies), len(script_bodies), missing or "none"))


if __name__ == "__main__":
    sys.exit(main())
