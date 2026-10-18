#!/usr/bin/env bash
# Packages the AppImage, then uploads it and its .zsync file to the
# v<pubspec version> release on Seth-Lamancusa/file-tile.
# Pass --skip-build to upload an AppImage that was already packaged.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
repo="Seth-Lamancusa/file-tile"

if [[ "${1:-}" != "--skip-build" ]]; then
  "$here/release.sh"
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "file-tile: gh is required to publish. Install it, then run: gh auth login" >&2
  exit 1
fi

version="$(awk '/^version:/ { print $2; exit }' "$root/pubspec.yaml")"
version="${version%%+*}"
tag="v${version}"
dir="$root/dist/${version}"

shopt -s nullglob
appimages=("$dir"/file_tile-*-linux.AppImage)
zsyncs=("$dir"/file_tile-*-linux.AppImage.zsync)
shopt -u nullglob

if [[ ${#appimages[@]} -ne 1 || ${#zsyncs[@]} -ne 1 ]]; then
  echo "file-tile: expected one AppImage and one .zsync in $dir" >&2
  echo "file-tile: install zsync (sudo apt install zsync) and package again if the .zsync file is missing." >&2
  exit 1
fi

if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
  gh release upload "$tag" --repo "$repo" --clobber "${appimages[0]}" "${zsyncs[0]}"
else
  gh release create "$tag" --repo "$repo" --title "$tag" --generate-notes \
    "${appimages[0]}" "${zsyncs[0]}"
fi

echo "file-tile: published ${appimages[0]##*/} and ${zsyncs[0]##*/} to $repo $tag"
