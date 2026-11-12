# Sunbar

Sunbar is a menu bar utility for the built-in Liquid Retina XDR display on Apple silicon. It requires macOS 14 or later and an HDR-capable display preset. The boost starts off on first launch. The sun icon opens the switch, boost slider, and optional **Open at Login** control.

## Build and launch

```sh
./build.sh --test
./build.sh
open build/Sunbar.app
```

The build uses Xcode or the Command Line Tools and signs the bundle for local use. Move `Sunbar.app` to Applications before enabling **Open at Login**.

## Check the gestures

1. Turn off **Extra Brightness** in Vorssaint and use the **Apple XDR Display** preset in System Settings. In Sunbar, select **Native HDR** under **Boost method** and turn on **XDR Brightness**.
2. Swipe up into Mission Control and expand the Spaces thumbnails. Swipe sideways slowly between two Spaces and pause mid-swipe.
3. If brightness dips or motion stutters, use **Copy Diagnostics** immediately afterward. The report includes available HDR headroom, the requested linear gain, and filter updates.

## How it works

**Native HDR** applies a floating-point color matrix through the macOS compositor. One backdrop window covers the display, and a corner HDR trigger keeps EDR active. The filter follows live desktop updates at the display's refresh rate. Screen Recording access is unnecessary for this mode. The old **Live HDR** preference migrates to **Native HDR**.

The implementation uses private Core Animation and SkyLight interfaces, checked at startup. Unsupported versions show an unavailable status. The current implementation has been tested on macOS 27.2.

**Direct Backlight** tries to raise the built-in panel's brightness through IOKit using Apple's stock SDR preset. It stops and restores your display settings when the preset caps the panel at its usual SDR level. A reported request or register value is a driver setting. The app restores the previous display settings on quit and recovers them on the next launch after an unexpected exit.

**System Layer** and **All Spaces** use Metal overlays. These modes can lose the boost during macOS gestures. Native HDR and the overlay modes pause during system authorization.

References include the [Core Animation backdrop interface](https://github.com/kageroumado/core-animation-private), [Apple's display reference modes](https://support.apple.com/en-euro/guide/mac-help/mchl50ecf3c4/mac), [Harmaline's framebuffer brightness control](https://github.com/kageroumado/harmaline/blob/main/Sources/Daemon/Recovery.swift), and the [Vorssaint Extra Brightness implementation](https://github.com/vorssaint/vorssaint-utils/blob/c007f6af59a30ce47997d2264398298fa363fb88/Sources/Vorssaint/Services/Display/ExtraBrightnessService.swift).
