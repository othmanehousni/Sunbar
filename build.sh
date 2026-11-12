#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

case "${1:-}" in
    ""|--test) ;;
    *) echo "Usage: ./build.sh [--test]" >&2; exit 2 ;;
esac

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
    xcrun swiftc "${flags[@]}" -o .build/BoostChecks Sources/BoostRamp.swift Tests/BoostChecks.swift
    .build/BoostChecks
    xcrun swiftc "${flags[@]}" -o .build/ControllerChecks Sources/BoostController.swift Sources/BoostRamp.swift Sources/CompositorBoost.swift Sources/HDRTrigger.swift Sources/PinnedSpace.swift Tests/ControllerChecks.swift
    .build/ControllerChecks -BoostEnabled NO
    exit
fi

app="build/Sunbar.app"
iconset=".build/Sunbar.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/sunbar.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" assets/sunbar.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp Info.plist "$app/Contents/Info.plist"
cp LICENSE ACKNOWLEDGEMENTS.md "$app/Contents/Resources/"
xcrun swiftc "${flags[@]}" -O -o "$app/Contents/MacOS/Sunbar" Sources/*.swift
signing_identity="${SUNBAR_SIGNING_IDENTITY:--}"
if [[ "$signing_identity" == - ]]; then
    codesign --force --options runtime --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$app"
fi
echo "$PWD/$app"
