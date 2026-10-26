# shellcheck shell=bash
# Example config.local.sh. Copy it to config.local.sh (not tracked by git) and
# keep only the lines you need. config.sh reads it first, so these values win.
#
# The values below match the first test install (2026-10-26), which used the
# earlier names: work folder ~/m3gpu, kernel suffix -m3gpu and /opt/mesa-m3.
# Use them on that machine so the installed kernel and Mesa keep matching.

# AGX_PROFILE=j516s
# AGX_ROOT="$HOME/m3gpu"
# LOCALVERSION=-m3gpu
# MESA_PREFIX=/opt/mesa-m3
# JOBS=10
