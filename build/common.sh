# shellcheck shell=bash
# Shared settings for the builds. Sourced by the other build scripts.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$REPO_DIR/config.sh"

mkdir -p "$SRC" "$OUT" "$LOGS"

# Run long builds detached from SSH so a dropped connection does not kill them:
#   systemd-run --user --unit=agx-kernel <repo>/build/build-kernel.sh
# A user unit stops when the user manager stops, so stay logged in on the
# desktop (or enable lingering) while it runs, and turn off automatic sleep.

# Fetch exactly one commit, without history, into $1.
fetch_pinned() {
	local dir="$1" repo="$2" commit="$3"
	if [ ! -d "$dir/.git" ]; then
		git init -q "$dir"
		git -C "$dir" config core.hooksPath /dev/null
		git -C "$dir" remote add origin "$repo"
	fi
	if [ "$(git -C "$dir" rev-parse -q --verify HEAD 2>/dev/null)" != "$commit" ]; then
		git -C "$dir" fetch -q --depth 1 origin "$commit"
		git -C "$dir" checkout -q --detach "$commit"
	fi
	echo "$(basename "$dir"): $(git -C "$dir" rev-parse HEAD)"
}
