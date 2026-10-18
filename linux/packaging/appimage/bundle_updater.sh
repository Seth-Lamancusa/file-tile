#!/usr/bin/env bash
# Pre-package hook. Copies appimageupdatetool into the Flutter bundle so it
# lands at AppDir/usr/bin/appimageupdatetool. flutter_distributor sets
# BUILD_OUTPUT_DIRECTORY. Set FILE_TILE_UPDATER_BIN to skip the download.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="$here/.cache"
default_src="$cache/appimageupdatetool-x86_64.AppImage"
url="https://github.com/AppImage/AppImageUpdate/releases/download/continuous/appimageupdatetool-x86_64.AppImage"
src="${FILE_TILE_UPDATER_BIN:-$default_src}"

if [[ ! -x "$src" ]]; then
  mkdir -p "$cache"
  curl -fL --retry 3 -o "$default_src" "$url"
  chmod +x "$default_src"
  src="$default_src"
fi

dest_root="${BUILD_OUTPUT_DIRECTORY:-}"
if [[ -z "$dest_root" ]]; then
  echo "bundle_updater: BUILD_OUTPUT_DIRECTORY is not set" >&2
  exit 1
fi

mkdir -p "$dest_root/usr/bin"
cp "$src" "$dest_root/usr/bin/appimageupdatetool"
chmod +x "$dest_root/usr/bin/appimageupdatetool"
