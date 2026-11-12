# Contributing to Sunbar

Use Swift 6 and a macOS toolchain that can target macOS 14 on Apple silicon.

```sh
./build.sh --test
./build.sh
```

## Display changes

Test changes on a built-in Liquid Retina XDR display using the Apple XDR Display preset. Check brightness and color at several slider positions, then test Mission Control, the expanded desktop previews, slow horizontal desktop swipes, full-screen apps, app switching, and sleep/wake. Confirm that quitting restores the ordinary display appearance.

CI checks the build and pure logic on macOS runners. HDR behavior needs a physical compatible display. Include the hardware and macOS version you tested in a pull request.

Preserve the calibrated sRGB multiplier and selector checks around private interfaces. Keep Native HDR as the default method.

## Experimental methods

The menu retains these development modes for diagnosis.

- **Direct Backlight** tries an IOKit backlight request under Apple's stock SDR preset. It stops and restores settings when the active preset caps the panel at normal SDR brightness. Its recovery journal is restored on the next launch after an interrupted run.
- **System Layer** and **All Spaces** use Metal multiply overlays. Their boost can disappear during compositor transitions.

## Bug reports

Include your Mac model, macOS version, Sunbar version, display preset, selected method, steps to reproduce, and the output of Copy Diagnostics.

## Assets and releases

The app icon is generated from `assets/sunbar.png` during the build. Artwork provenance is in `assets/README.md`. Packaging and notarization instructions are in `docs/RELEASING.md`.

Contributions are distributed under GPL-3.0-only.
