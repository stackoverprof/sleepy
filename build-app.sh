#!/bin/zsh

set -euo pipefail

configuration="${1:-debug}"
case "$configuration" in
  debug|release) ;;
  *)
    echo "Usage: ./build-app.sh [debug|release]"
    exit 2
    ;;
esac

swift build -c "$configuration"

bundle_dir="$PWD/dist/Sleepy.app"
executable_path="$PWD/.build/$configuration/Sleepy"
helper_path="$PWD/.build/$configuration/SleepyHelper"

rm -rf "$bundle_dir"
mkdir -p "$bundle_dir/Contents/MacOS"
mkdir -p "$bundle_dir/Contents/Library/PrivilegedHelperTools"
mkdir -p "$bundle_dir/Contents/Library/LaunchDaemons"
cp "$executable_path" "$bundle_dir/Contents/MacOS/Sleepy"
cp "$helper_path" "$bundle_dir/Contents/Library/PrivilegedHelperTools/com.erbin.sleepy.helper"
cp "$PWD/Resources/Info.plist" "$bundle_dir/Contents/Info.plist"
cp "$PWD/Resources/com.erbin.sleepy.helper.plist" "$bundle_dir/Contents/Library/LaunchDaemons/com.erbin.sleepy.helper.plist"

codesign --force --sign - --identifier com.erbin.sleepy.helper \
  "$bundle_dir/Contents/Library/PrivilegedHelperTools/com.erbin.sleepy.helper"
codesign --force --deep --sign - --identifier com.erbin.sleepy "$bundle_dir"

echo "$bundle_dir"
