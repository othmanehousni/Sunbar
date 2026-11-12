Sunbar brings extra XDR brightness to the built-in Liquid Retina XDR display on Apple silicon MacBook Pro.

- Native HDR keeps brightness across apps, Mission Control, full-screen windows, and desktop swipes.
- Adjust the boost with an aligned slider and visible percentage, and optionally start Sunbar at login.
- The native compositor is the only brightness method. Experimental overlays, direct backlight control, and diagnostic collection have been removed.
- Includes the Sunbar icon, source build scripts.
- Hardened runtime is enabled without exception entitlements. The app makes no network requests and requires no Screen Recording or Accessibility access.

This beta is ad-hoc signed and has not been notarized. After the first launch attempt, macOS may require approval under System Settings → Privacy & Security → Open Anyway. Source builds are supported through the README instructions.

The verified configuration is MacBookPro18,3 on macOS 27.2. The project targets macOS 14 and later on arm64. Native HDR uses private macOS compositor interfaces, and other system versions need hardware testing.

Download the ZIP, move Sunbar.app to Applications, then enable XDR Brightness in the sun menu. SHA256SUMS is provided for verifying the archive.

Licensed under GPL-3.0-only. Source code and contribution instructions are available in the public Sunbar repository.
