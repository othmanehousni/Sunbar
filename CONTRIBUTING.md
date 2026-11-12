# Contributing to Sunbar

Use Swift 6 and a macOS toolchain that can target macOS 14 on Apple silicon.

```sh
./build.sh --test
./build.sh
```

## Display changes

Test changes on a built-in Liquid Retina XDR display using the Apple XDR Display preset. Check brightness and color at several slider positions, then test Mission Control, the expanded desktop previews, slow horizontal desktop swipes, full-screen apps, app switching, and sleep/wake. Confirm that quitting restores the ordinary display appearance.

CI checks the build and pure logic on macOS runners. HDR behavior needs a physical compatible display. Include the hardware and macOS version you tested in a pull request.

Preserve the calibrated sRGB multiplier, selector checks around private interfaces, and pause behavior for sleep, inactive sessions, and system authorization UI. The native compositor is the only brightness backend. Avoid display preset changes, hardware backlight writes, and screen capture.

## Bug reports

Include your Mac model, macOS version, Sunbar version, display preset, and steps to reproduce. Describe whether the problem occurs during normal use, Mission Control, full-screen apps, or desktop swipes. Report security vulnerabilities privately using the security policy.

## Assets and releases

The app icon is generated from `assets/sunbar.png` during the build. Artwork provenance is in `assets/README.md`. Packaging and notarization instructions are in `docs/RELEASING.md`.

Contributions are distributed under GPL-3.0-only.
