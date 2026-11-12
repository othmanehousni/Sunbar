# Security

Report vulnerabilities privately through [GitHub security advisories](https://github.com/othmanehousni/Sunbar/security/advisories/new). Include the affected version, macOS version, and steps to reproduce. Keep sensitive information out of public issues. Fixes target the latest release.

## App behavior

Sunbar runs as your user, without administrator privileges, privileged helpers, or a background service. It does not record the screen, read keyboard input, collect diagnostics, send analytics, or make network requests. Opening the source link launches your browser. Open at Login uses macOS Service Management and is optional.

The app stores its enabled state and boost strength in local preferences. It applies a visual filter through private macOS compositor interfaces without changing display presets or writing hardware backlight registers. The filter and HDR trigger are removed when the boost stops or the app quits. Sleep and inactive-session notifications also stop the boost. System authorization UI pauses it.

Release builds enable Apple's hardened runtime without exception entitlements. The current beta is ad-hoc signed and is not Apple notarized. The checksum detects a changed download when compared with a trusted copy of the published checksum. It does not replace Developer ID signing.

Sunbar is not sandboxed and has the ordinary file access of an unsandboxed macOS app. Compatibility and display behavior need testing on each supported hardware and macOS configuration.
