#!/bin/zsh
# Build an isolated development app: demo data only, separate identity, no
# writes to the user's state, login items, notifications or window preferences.
set -eu
cd "${0:A:h}/.."
APP="$PWD/.build/development-preview/缓芽预览.app"
zsh scripts/build.sh "$(uname -m)" "$APP"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier app.riseup.desktop.preview' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 缓芽预览' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 缓芽预览' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 2.0.0' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :HuanyaPreviewMode bool true' "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
if [[ "${1:-}" == "--build-only" ]]; then
    echo "开发预览已构建：$APP"
else
    open -n "$APP" --args --preview
fi
