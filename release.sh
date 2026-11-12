#!/bin/bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

if [[ $# -ne 0 ]]; then
    echo "Usage: ./release.sh" >&2
    exit 2
fi

if [[ -n "${SUNBAR_NOTARY_PROFILE:-}" ]]; then
    if [[ -z "${SUNBAR_SIGNING_IDENTITY:-}" || "$SUNBAR_SIGNING_IDENTITY" == - ]]; then
        echo "Notarization requires SUNBAR_SIGNING_IDENTITY to name a Developer ID Application certificate." >&2
        exit 2
    fi
    xcrun --find notarytool >/dev/null
fi

./build.sh --test
./build.sh
app="build/Sunbar.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
if [[ "${GITHUB_REF_TYPE:-}" == tag && "${GITHUB_REF_NAME:-}" != "v$version" ]]; then
    echo "The release tag must match v$version from Info.plist." >&2
    exit 2
fi

codesign --verify --strict "$app"
archive="Sunbar-$version-macos-arm64.zip"
stage_dir=$(mktemp -d build/release.XXXXXX)
trap 'rm -f "$stage_dir/$archive" "$stage_dir/SHA256SUMS"; rmdir "$stage_dir"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage_dir/$archive"
if [[ -n "${SUNBAR_NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$stage_dir/$archive" --keychain-profile "$SUNBAR_NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl --assess --type execute --verbose "$app"
    rm -f "$stage_dir/$archive"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$stage_dir/$archive"
fi

(cd "$stage_dir" && shasum -a 256 "$archive" > SHA256SUMS)
mv "$stage_dir/$archive" "build/$archive"
mv "$stage_dir/SHA256SUMS" build/SHA256SUMS
echo "$PWD/build/$archive"
echo "$PWD/build/SHA256SUMS"
