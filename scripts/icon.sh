#!/bin/zsh
set -eu
cd "${0:A:h}/.."
source scripts/toolchain.sh
xcrun swiftc -swift-version 5 "${RISEUP_SWIFT_FLAGS[@]}" Sources/BrandArtwork.swift scripts/make-icon.swift -o .build/MakeIcon
.build/MakeIcon .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o Resources/AppIcon.icns
