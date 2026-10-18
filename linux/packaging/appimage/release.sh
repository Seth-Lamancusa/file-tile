#!/usr/bin/env bash
# Packages the Linux AppImage with the updater bundled and, when
# update_information has an uncommented line, embedded in the AppImage header.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
export PATH="$here/bin:${PATH:-}"

if ! command -v zsyncmake >/dev/null 2>&1; then
  echo "file-tile: zsyncmake is not installed, so no .zsync delta file will be written." >&2
  echo "file-tile: install it with: sudo apt install zsync" >&2
fi

cd "$root"
exec flutter_distributor release --name production "$@"
