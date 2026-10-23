#!/bin/zsh
set -eu
cd "${0:A:h}/.."
RISEUP_ARCH="${1:-$(uname -m)}"
case "$RISEUP_ARCH" in
    x86_64|arm64) ;;
    *) echo "不支持的架构：$RISEUP_ARCH；请使用 x86_64 或 arm64。" >&2; exit 2 ;;
esac
if (( $# == 0 )); then
    APP="$PWD/dist/缓芽.app"
else
    APP="${2:-$PWD/dist/$RISEUP_ARCH/缓芽.app}"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/module-cache
source scripts/toolchain.sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
xcrun swiftc -swift-version 5 -O -target "$RISEUP_ARCH-apple-macosx13.0" "${RISEUP_SWIFT_FLAGS[@]}" Sources/Core.swift Sources/Planning.swift Sources/BrandArtwork.swift Sources/SystemIntegration.swift Sources/AppModel.swift Sources/Views.swift Sources/PlanningViews.swift Sources/ReviewViews.swift Sources/main.swift -o "$APP/Contents/MacOS/RiseUp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSArchitecturePriority array' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSArchitecturePriority:0 string $RISEUP_ARCH" "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"; fi
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
RISEUP_ACTUAL_ARCH="$(lipo -archs "$APP/Contents/MacOS/RiseUp")"
if [[ "$RISEUP_ACTUAL_ARCH" != "$RISEUP_ARCH" ]]; then
    echo "架构校验失败：期望 $RISEUP_ARCH，实际 $RISEUP_ACTUAL_ARCH" >&2
    exit 1
fi
echo "已构建 [$RISEUP_ARCH]：$APP"
