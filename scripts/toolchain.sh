#!/bin/zsh
# Some upgraded Command Line Tools installations retain the obsolete Swift
# module map alongside bridging.modulemap. Hide only that stale file from the
# compiler using a project-local virtual filesystem; never alter the SDK.
mkdir -p "$PWD/.build/module-cache"
RISEUP_SWIFT_FLAGS=(-module-cache-path "$PWD/.build/module-cache")
RISEUP_INCLUDE="$(xcode-select -p)/usr/include/swift"
if [[ -f "$RISEUP_INCLUDE/module.modulemap" && -f "$RISEUP_INCLUDE/bridging.modulemap" ]] && /usr/bin/grep -q 'module SwiftBridging' "$RISEUP_INCLUDE/module.modulemap" && /usr/bin/grep -q 'module SwiftBridging' "$RISEUP_INCLUDE/bridging.modulemap"; then
    if [[ ! -f .build/empty.modulemap ]]; then
        echo '// Legacy module map hidden by RiseUp build compatibility overlay.' > .build/empty.modulemap
    fi
    RISEUP_OVERLAY="$PWD/.build/toolchain-overlay-$$.json"
    cat > "$RISEUP_OVERLAY" <<EOF
{"version":0,"roots":[{"type":"file","name":"$RISEUP_INCLUDE/module.modulemap","external-contents":"$PWD/.build/empty.modulemap"}]}
EOF
    RISEUP_SWIFT_FLAGS+=(-vfsoverlay "$RISEUP_OVERLAY" -Xcc -ivfsoverlay -Xcc "$RISEUP_OVERLAY")
fi
