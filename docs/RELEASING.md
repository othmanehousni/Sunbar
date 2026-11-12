# Releasing Sunbar

## Build a release candidate

Update the version and increasing build number in `Info.plist`, then run the release script from a clean checkout.

```sh
./release.sh
```

For version 0.6.0 it creates `build/Sunbar-0.6.0-macos-arm64.zip` and `build/SHA256SUMS`. The ZIP contains `Sunbar.app`, its icon, license, and acknowledgements. The default signature is ad hoc. GitHub Actions builds the same package on macOS 15 and macOS 26.

Verify the package contents, then test the extracted app on an XDR Mac. Check the release version, icon, startup, boost slider, Mission Control, desktop swipes, full-screen apps, app switching, login item, sleep/wake, and quit behavior.

## Developer ID signing and notarization

A notarized download requires a Developer ID Application certificate and access to Apple's notarization service. Install the signing identity in your Keychain and list it with the following command.

```sh
security find-identity -v -p codesigning
```

Store notarization credentials using the secure interactive prompts.

```sh
xcrun notarytool store-credentials Sunbar
```

Build, sign with the hardened runtime and a timestamp, notarize, staple, assess with Gatekeeper, and package the final app through the release script.

```sh
export SUNBAR_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export SUNBAR_NOTARY_PROFILE='Sunbar'
./release.sh
```

The script stops when signing, submission, stapling, validation, or assessment fails. Keep certificate keys and credentials in the Keychain or repository secrets.

Apple documents the signing and notarization requirements in its distribution guide. [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

## Publish

Confirm the Build workflow is green for the release commit. Create a version tag that matches `Info.plist`, then create a draft release with the ZIP and checksum. The commands below use the active GitHub account.

```sh
git tag -a v0.6.0 -m 'Sunbar 0.6.0'
git push origin v0.6.0
gh release create v0.6.0 \
  build/Sunbar-0.6.0-macos-arm64.zip build/SHA256SUMS \
  --draft --prerelease --title 'Sunbar 0.6.0' \
  --notes-file docs/RELEASE_NOTES.md
```

For an ad-hoc signed beta, state its signing status in the release notes. Publish the draft when its source commit, install instructions, signing status, and downloads have been reviewed. A public repository makes the corresponding source available alongside the binary.
