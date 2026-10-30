# libfprint with the aurora driver: build plan for the next sudo window (written 2026-10-28, run 2026-10-30, see the result below)

Goal: build an RPM of libfprint 1.94.100 plus the aurora Apple SEP driver on the M3, under a private prefix (`/opt/aurora-sep`). Do not install it. The distro `libfprint` and `fprintd` stay as they are. This builds the userspace half only; it does not show that Touch ID works through fprintd.

## 1. State on the M3 (checked read-only 2026-10-28)

- Installed: `libfprint` 1.94.100-1.fc44, `fprintd` 1.94.5, `rpm-build` 6.0.2, `meson`, `ninja-build`, `gcc`, `gcc-c++`, `glib2-devel`, `openssl-devel`.
- Missing build dependencies (they match the list from the failed configure): `gusb`, `gudev-1.0`, `pixman-1`, `nss`, `cairo`, `libusb-1.0`, `gobject-introspection-1.0` (as pkg-config names). `rpmdevtools` is not needed.
- Not on the M3: the libfprint source. The aurora patch is: `~/m3gpu/src/linux/tools/aurora-sep/patches/libfprint-1.94.100-apple-sep.patch` (sha256 `9ddaa1790a5699f94beb9a2b64b41caf843c9732561bd81c77030e662d95e112`).
- The recipe is the spec `tools/touchid/packaging/libfprint-aurora.spec` in this repository. A copy is on the M3 at `~/m3gpu/aurora-rpm-test/libfprint-aurora.spec`. `rpmspec` parses it and lists the nine pkg-config build requirements above plus the compilers and meson.
- The package manager metadata was not cached, so the exact `-devel` package names were not checked here. The `builddep` command below takes the names from the spec, so no name is guessed.

## 2. Preconditions

- AC power is connected: `cat /sys/class/power_supply/macsmc-ac/online` prints `1`.
- No test boot is running and no other session needs the CPU (the build takes minutes).
- Only step 3 needs sudo. Every other step runs as the user.

## 3. Build dependencies (sudo)

```bash
mkdir -p ~/aurora-build && cp ~/m3gpu/aurora-rpm-test/libfprint-aurora.spec ~/aurora-build/
sudo dnf builddep ~/aurora-build/libfprint-aurora.spec
```
Read the transaction before answering yes. It must only add `-devel` packages and their libraries. If it wants to remove or upgrade an installed package, stop. Fallback by package name (names not verified offline): `sudo dnf install libgusb-devel libgudev-devel pixman-devel nss-devel cairo-devel libusb1-devel gobject-introspection-devel`.

## 4. Source (network, no sudo)

The source comes from the Fedora source package of the same version. Its signature is the integrity check, because no checksum for the upstream tarball is known in advance.

```bash
mkdir -p ~/aurora-build/srpm ~/aurora-build/rpmbuild/SOURCES ~/aurora-build/rpmbuild/SPECS && cd ~/aurora-build/srpm
dnf download --source libfprint
rpm -q libfprint
rpm -K libfprint-*.src.rpm
```
- `rpm -K` must say the digests and signatures are OK (the Fedora key is in the RPM database).
- The version and release in the file name must equal `rpm -q libfprint` (`1.94.100-1.fc44`).
- If `dnf download --source` finds no source repository, use the Koji copy: `https://kojipkgs.fedoraproject.org/packages/libfprint/1.94.100/1.fc44/src/libfprint-1.94.100-1.fc44.src.rpm` (URL pattern, check it). The upstream tag tarball is `https://gitlab.freedesktop.org/libfprint/libfprint/-/archive/v1.94.100/libfprint-v1.94.100.tar.gz`; it is only a second source to compare with (`diff -r` of the two trees).

## 5. Prepare the sources (no sudo)

```bash
cd ~/aurora-build/srpm && rpm2cpio libfprint-1.94.100-1.fc44.src.rpm | cpio -idm
tar tzf libfprint-v1.94.100.tar.gz | head -1          # must print libfprint-v1.94.100/
sha256sum libfprint-v1.94.100.tar.gz                   # write the value into the build notes
cp libfprint-v1.94.100.tar.gz ~/aurora-build/rpmbuild/SOURCES/
cp ~/m3gpu/src/linux/tools/aurora-sep/patches/libfprint-1.94.100-apple-sep.patch ~/aurora-build/rpmbuild/SOURCES/
sha256sum ~/aurora-build/rpmbuild/SOURCES/libfprint-1.94.100-apple-sep.patch   # must equal the value in section 1
cp ~/aurora-build/libfprint-aurora.spec ~/aurora-build/rpmbuild/SPECS/
```
The Fedora patches and spec in the source package are not used: only its `Source0` tarball. If the tarball unpacks to another directory name, change `%autosetup -n` in the spec to match.

Check that the patch fits the tarball before the build:
```bash
mkdir -p ~/aurora-build/check && tar xzf ~/aurora-build/rpmbuild/SOURCES/libfprint-v1.94.100.tar.gz -C ~/aurora-build/check
cd ~/aurora-build/check/libfprint-v1.94.100 && git apply --check ~/aurora-build/rpmbuild/SOURCES/libfprint-1.94.100-apple-sep.patch && echo patch-fits
```
If the check fails, the Fedora tarball differs from the upstream tag the patch was made for. Stop and use `git clone --depth 1 --branch v1.94.100` of the upstream repository instead (the aurora README way), packed into a tarball with the same name.

## 6. Build (no sudo, a few minutes)

```bash
cd ~/aurora-build && rpmbuild --define "_topdir $HOME/aurora-build/rpmbuild" -ba rpmbuild/SPECS/libfprint-aurora.spec 2>&1 | tee build.log
```
`%check` runs `meson test`. The aurora README reports 0 failures on aarch64, with most device tests skipped. Any failure is a stop.

## 7. Checks (read-only)

```bash
ls ~/aurora-build/rpmbuild/RPMS/aarch64/
rpm -qpl ~/aurora-build/rpmbuild/RPMS/aarch64/libfprint-aurora-1.94.100-1.*.rpm | head -20     # files only under /opt/aurora-sep
rpm -qpR ~/aurora-build/rpmbuild/RPMS/aarch64/libfprint-aurora-1.94.100-1.*.rpm
ls /opt/aurora-sep 2>&1; rpm -q libfprint                                                       # still absent / unchanged
```
The package must list only paths under `/opt/aurora-sep`. To look for the driver inside the library, unpack the RPM into a scratch folder (`rpm2cpio ... | cpio -idm`) and run `strings` on the library there.

## 8. Not done on purpose

- No `rpm -i` or `dnf install` of the built package. Installing needs its own yes: copy to `/opt/aurora-sep`, the SELinux label for the private library directory, and a fprintd drop-in with `LD_LIBRARY_PATH=/opt/aurora-sep/lib64` and device access to `/dev/sep-bio` (see section 7 of the stage 3b plan).
- No change to PAM. No enable of fingerprint login. Touch ID stays off login, sudo and the lock screen until the many-trial test of the stage 3b plan passes.

## 9. Stop rules

- AC is not online.
- The `dnf` transaction removes or upgrades an installed package.
- `rpm -K` does not say OK, or the version differs from the installed `libfprint`.
- The patch check fails, meson rejects an option (the option names are the ones in the aurora README plus `udev_rules=disabled`, `udev_hwdb=disabled` (feature options; `false` is refused, found 2026-10-30)), or `%check` fails.
- Anything asks for sudo after step 3.

## 10. Result (2026-10-30 02:12 to 02:21, sudo window, M3 on battery at 100 %)

- Step 3: `dnf builddep` added 38 packages and upgraded `libbrotli` 1.2.0 to 1.2.1 (user approved the upgrade). All seven pkg-config names now resolve.
- Step 4: `dnf download --source libfprint` gave `libfprint-1.94.100-1.fc44.src.rpm`, `rpm -K`: digests signatures OK, same version as the installed `libfprint`. (dnf as the user also offered to import the Tailscale repository key; the prompt got no answer, so nothing was imported.)
- Step 5: tarball `libfprint-v1.94.100.tar.gz`, sha256 `edc90e02f330a7595ceaf37f2c6ec32ed43541347fe936d3273b0bb2524fd19c`; aurora patch sha256 matches; `git apply --check`: patch-fits.
- Step 6: the first build stopped at meson: `udev_rules` and `udev_hwdb` are feature options, so `false` is refused. The spec now uses `disabled`. Second build: exit 0 in 16 s, meson tests Ok 5, Fail 0, Skipped 32.
- Step 7: `libfprint-aurora-1.94.100-1.fc44.aarch64.rpm`, 354,984 bytes, sha256 `f6926eb82b8d26d2885c159a50bbddafc753cd5b025cbeca5e28779481aab378`, 19 files, 0 outside `/opt/aurora-sep`. The library has the `aurora_*` driver functions. `/opt/aurora-sep` does not exist and `libfprint` is unchanged: nothing installed.
- The RPM stays on the M3 in `~/aurora-build/rpmbuild/RPMS/aarch64/`.
