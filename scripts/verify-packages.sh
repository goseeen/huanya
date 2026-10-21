#!/bin/zsh
set -eu
cd "${0:A:h}/.."
RISEUP_ROOT="$PWD"
RISEUP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
RISEUP_PACKAGE_ROOT="$RISEUP_ROOT/dist/releases/$RISEUP_VERSION"
RISEUP_ARCHES=("$@")
if (( $# == 0 )); then RISEUP_ARCHES=(x86_64 arm64); fi
for RISEUP_ARCH in "${RISEUP_ARCHES[@]}"; do
    case "$RISEUP_ARCH" in
        x86_64|arm64) ;;
        *) echo "不支持的架构：$RISEUP_ARCH；请使用 x86_64 或 arm64。" >&2; exit 2 ;;
    esac
done
RISEUP_MOUNT=""
trap 'if [[ -n "$RISEUP_MOUNT" ]]; then hdiutil detach -quiet "$RISEUP_MOUNT" || true; fi' EXIT

for RISEUP_ARCH in "${RISEUP_ARCHES[@]}"; do
    if [[ "$RISEUP_ARCH" == x86_64 ]]; then RISEUP_LABEL=Intel; else RISEUP_LABEL=AppleSilicon; fi
    RISEUP_DMG="$RISEUP_PACKAGE_ROOT/huanya-$RISEUP_VERSION-$RISEUP_LABEL-$RISEUP_ARCH.dmg"
    RISEUP_MOUNT="$RISEUP_ROOT/.build/verify-$RISEUP_ARCH-$$"
    mkdir -p "$RISEUP_MOUNT"
    hdiutil attach -readonly -nobrowse -noautoopen -quiet -mountpoint "$RISEUP_MOUNT" "$RISEUP_DMG"
    RISEUP_APP="$RISEUP_MOUNT/缓芽.app"
    RISEUP_BINARY="$RISEUP_APP/Contents/MacOS/RiseUp"
    [[ "$(lipo -archs "$RISEUP_BINARY")" == "$RISEUP_ARCH" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSArchitecturePriority:0' "$RISEUP_APP/Contents/Info.plist")" == "$RISEUP_ARCH" ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$RISEUP_APP/Contents/Info.plist")" == 13.0 ]]
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$RISEUP_APP/Contents/Info.plist")" == "$RISEUP_VERSION" ]]
    [[ "$(readlink "$RISEUP_MOUNT/Applications")" == /Applications ]]
    [[ -s "$RISEUP_MOUNT/安装说明.txt" ]]
    codesign --verify --deep --strict "$RISEUP_APP"
    cmp "$RISEUP_BINARY" "$RISEUP_ROOT/dist/$RISEUP_ARCH/缓芽.app/Contents/MacOS/RiseUp"
    file "$RISEUP_BINARY"
    hdiutil detach -quiet "$RISEUP_MOUNT"
    RISEUP_MOUNT=""
    echo "PASS [$RISEUP_ARCH]：安装包挂载、原生架构、签名、应用内容、安装入口和系统版本。"
done
(
    cd "$RISEUP_PACKAGE_ROOT"
    shasum -a 256 -c SHA256SUMS.txt
)
