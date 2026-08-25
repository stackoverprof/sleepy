#!/bin/zsh

# Builds the release app and wraps it in a drag-to-Applications disk image at
# dist/Sleepy-<version>.dmg.

set -euo pipefail

cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
image="$PWD/dist/Sleepy-$version.dmg"

./build-app.sh release > /dev/null

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

cp -R "$PWD/dist/Sleepy.app" "$staging/Sleepy.app"
ln -s /Applications "$staging/Applications"

rm -f "$image"
hdiutil create \
  -volname "Sleepy $version" \
  -srcfolder "$staging" \
  -fs HFS+ \
  -format UDZO \
  -quiet \
  "$image"

echo "$image"
