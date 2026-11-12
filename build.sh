#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

flags=(-swift-version 6 -target arm64-apple-macos14.0 -sdk "$(xcrun --sdk macosx --show-sdk-path)")
mkdir -p .build

# Some Command Line Tools installations contain both the old and new SwiftBridging maps.
# Hide the duplicate for this build without changing the toolchain installation.
swift_headers="$(xcode-select -p)/usr/include/swift"
if [[ -f "$swift_headers/module.modulemap" && -f "$swift_headers/bridging.modulemap" ]] &&
    cmp -s <(sed -n '/^module /,$p' "$swift_headers/module.modulemap") \
           <(sed -n '/^module /,$p' "$swift_headers/bridging.modulemap"); then
    : > .build/empty.modulemap
    cat > .build/clang-overlay.json <<EOF
{"version":0,"overlay-relative":true,"roots":[{"type":"file","name":"$swift_headers/module.modulemap","external-contents":"empty.modulemap"}]}
EOF
    overlay="$PWD/.build/clang-overlay.json"
    flags+=(-vfsoverlay "$overlay" -Xcc -ivfsoverlay -Xcc "$overlay")
fi

if [[ "${1:-}" == --test ]]; then
    xcrun swiftc "${flags[@]}" -o .build/BoostChecks Sources/BoostRamp.swift Sources/OverlayGeometry.swift Sources/NativeBacklight.swift Tests/BoostChecks.swift
    .build/BoostChecks
    exit
fi

app="build/Sunbar.app"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"
xcrun swiftc "${flags[@]}" -O -o "$app/Contents/MacOS/Sunbar" Sources/*.swift
codesign --force --sign - "$app"
echo "$PWD/$app"
