#!/bin/zsh
set -eu
cd "${0:A:h}/.."
source scripts/toolchain.sh
xcrun swiftc -swift-version 5 "${RISEUP_SWIFT_FLAGS[@]}" Sources/Core.swift Tests/CoreTests.swift -o .build/CoreTests
.build/CoreTests
xcrun swiftc -swift-version 5 "${RISEUP_SWIFT_FLAGS[@]}" Sources/Core.swift Sources/SystemIntegration.swift Sources/AppModel.swift Tests/AppModelTests.swift -o .build/AppModelTests
.build/AppModelTests
