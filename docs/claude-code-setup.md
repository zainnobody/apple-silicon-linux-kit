# Set up the M3 with Claude Code

Claude Code can run the guide with you. It runs the commands, checks each result and stops at every step that needs you. You still type every password, do every reboot, and touch the Touch ID key yourself.

This page has two parts: connect a Mac to the M3, then paste the prompt.

## Choose where Claude Code runs

| Option | When to use it |
|---|---|
| **A. On a second Mac, over SSH (recommended)** | Claude Code keeps working while the M3 reboots, and it can help with the rollback from macOS. |
| **B. On the M3 itself** | You have no second computer. Claude Code stops at each reboot, and you start it again after the boot. |

Install Claude Code from [claude.com/claude-code](https://claude.com/claude-code) on the computer you choose.

## Option A: connect a Mac to the M3

Do these steps once. They take about 5 minutes.

1. On the M3 (Fedora), turn on the SSH server:

   ```bash
   sudo systemctl enable --now sshd
   ```

2. On the M3, read its local name. The Mac uses it to connect:

   ```bash
   hostnamectl --static
   ```

3. On the Mac, make a key if you have none:

   ```bash
   ssh-keygen -t ed25519
   ```

4. On the Mac, copy the key to the M3. Replace `USER` with your Linux user name and `NAME` with the name from step 2. Type your Linux password once:

   ```bash
   ssh-copy-id USER@NAME.local
   ```

5. On the Mac, add a short name. Open `~/.ssh/config` and add these lines:

   ```
   Host m3
       HostName NAME.local
       User USER
       ServerAliveInterval 30
   ```

6. On the Mac, test it. It must print the board name with no password prompt:

   ```bash
   ssh m3 cat /proc/device-tree/model
   ```

If `NAME.local` does not resolve, both computers must be on the same network. On public Wi-Fi, use a private network such as Tailscale instead, and do not open ports.

## The prompt

Open Claude Code in an empty folder on the Mac (Option A) or on the M3 (Option B). Paste this prompt. For Option B, change the first line to "You run on the M3 itself."

```text
You help me install the Apple Silicon Linux Kit on my MacBook Pro M3 Pro (J516S),
which already runs Fedora Asahi Remix 44 (KDE). The M3 is reachable with `ssh m3`.

Source of truth: GUIDE.md in https://github.com/zainnobody/apple-silicon-linux-kit.
On the M3, follow GUIDE.md Step 1 to clone the three repositories into ~/apple-silicon-linux.
Read GUIDE.md sections 1 to 5 before you run anything. Then show me a short plan:
the steps I want, which ones reboot, and where you need me.

Features I want (delete what you do not want):
- GPU, memory speed and the desktop on the GPU (steps 0 to 6)
- Feature fixes (step 7): Bluetooth, fans, video decode, USB-C displays, camera
- Mac-like desktop and lock screen (step 9)
- LocalSend file sharing (step 10)
- Touch ID (section 6)

How to work:
- Run one guide step at a time. After each step, run its "Verify" commands and show
  me the result in one or two lines. If a verify check fails, stop and tell me.
- Be fast: start long builds in the background (the guide uses systemd-run for the
  kernel), and read the next step while they run. Do not poll in a tight loop.
- After every reboot, reconnect and run `tests/m3-selftest.sh --quick` from the kit.
  Report the PASS, WARN and FAIL counts.
- Keep a short log of what you ran and what changed in ~/apple-silicon-linux/setup-log.md.

Stop and wait for me:
- Before every sudo command. I type the password myself in my own terminal.
  Never ask me for a password, never type one, never store one.
- Before every reboot. Tell me which kernel the next boot uses and how to undo it.
- Before stage C, until I confirm that I rehearsed the rollback in GUIDE.md section 4.
- For Touch ID: before every step of GUIDE.md section 6. Take and copy the xART backup
  first. Never restore an older xART backup. After any STOP or alarm from a Touch ID
  tool, do nothing more until I say so.

Never:
- Run the research items in GUIDE.md Step 11 (Neural Engine, video encode).
- Force an unknown GPU firmware with the prefix override.
- Change the macOS side, the startup disk or the boot volume, except the guide's
  rollback when I ask for it.
- Download anything that the guide does not name without asking me first.
```

## What to expect

- The kernel build is the longest step. It runs in the background on the M3.
- Stages C, D and E each need one reboot. The stock kernel stays in GRUB as the fallback.
- Claude Code asks you for every sudo password prompt, every reboot and every Touch ID touch.
- If something fails, Claude Code shows the verify output and the undo step from the guide.

## If the M3 does not boot

Use the rollback in [GUIDE.md section 4](../GUIDE.md#rollback-from-macos-when-fedora-does-not-boot). With Option A, Claude Code on the Mac can guide you through it while the M3 runs macOS.
