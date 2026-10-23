#!/bin/zsh
set -eu
cd "${0:A:h}/.."
source scripts/toolchain.sh
xcrun swiftc -swift-version 5 "${RISEUP_SWIFT_FLAGS[@]}" Sources/Core.swift Sources/Planning.swift Tests/CoreTests.swift -o .build/CoreTests
.build/CoreTests
xcrun swiftc -swift-version 5 "${RISEUP_SWIFT_FLAGS[@]}" Sources/Core.swift Sources/Planning.swift Sources/SystemIntegration.swift Sources/AppModel.swift Tests/AppModelTests.swift -o .build/AppModelTests
.build/AppModelTests
xcrun swiftc -swift-version 5 "${RISEUP_SWIFT_FLAGS[@]}" Sources/Core.swift Sources/Planning.swift Tests/PlanningTests.swift -o .build/PlanningTests
.build/PlanningTests
xcrun swiftc -swift-version 5 "${RISEUP_SWIFT_FLAGS[@]}" Sources/Core.swift Sources/Planning.swift Sources/SystemIntegration.swift Sources/AppModel.swift Tests/PlanningModelTests.swift -o .build/PlanningModelTests
.build/PlanningModelTests
