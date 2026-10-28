# libfprint 1.94.100 with the aurora Apple SEP driver, installed under a private prefix so that the distro libfprint stays
# untouched. Built from the Fedora source tarball (Source0 of the Fedora libfprint source package) plus the patch from
# the kernel tree (tools/aurora-sep/patches/libfprint-1.94.100-apple-sep.patch). Plan: docs/features/touchid-libfprint-build-plan.md
%global debug_package %{nil}
%global aurora_prefix /opt/aurora-sep

Name:           libfprint-aurora
Version:        1.94.100
Release:        1%{?dist}
Summary:        libfprint with the Apple SEP (aurora) driver, private prefix
License:        LGPL-2.1-or-later
URL:            https://gitlab.freedesktop.org/libfprint/libfprint
Source0:        libfprint-v%{version}.tar.gz
Patch0:         libfprint-1.94.100-apple-sep.patch

BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gusb)
BuildRequires:  pkgconfig(gudev-1.0)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(nss)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(libusb-1.0)
BuildRequires:  pkgconfig(openssl)
BuildRequires:  pkgconfig(gobject-introspection-1.0)

%description
libfprint 1.94.100 plus the aurora driver for the Apple SEP biometric device (/dev/sep-bio). Installed under
%{aurora_prefix}; fprintd loads it through a service drop-in (LD_LIBRARY_PATH). Not a replacement for the distro libfprint.

%prep
%autosetup -n libfprint-v%{version} -p1

%build
meson setup build --prefix=%{aurora_prefix} --libdir=lib64 -Ddrivers=default -Dintrospection=false \
    -Dgtk-examples=false -Ddoc=false -Dinstalled-tests=false -Dudev_rules=false -Dudev_hwdb=false
ninja -C build

%check
meson test -C build --print-errorlogs

%install
DESTDIR=%{buildroot} ninja -C build install

%files
%{aurora_prefix}

%changelog
* Wed Oct 28 2026 Touch ID session <noreply@example.invalid> - 1.94.100-1
- First local build recipe, private prefix, no install
