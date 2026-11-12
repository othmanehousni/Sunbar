// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import AppKit

@main
struct ControllerChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let controller = BoostController()
        precondition(!controller.enabled, "Run with -BoostEnabled NO")
        let center = NSWorkspace.shared.notificationCenter
        controller.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))

        // macOS can announce an inactive session before didFinishLaunching.
        center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        controller.enabled = true
        controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        precondition(controller.status == "Waiting for the display.")
        precondition(overlayCount() == 0)

        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        precondition(controller.status != "Waiting for the display.")
        if NSScreen.screens.contains(where: { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 2.05 }) {
            precondition(controller.status != "Native HDR is unavailable on this macOS version.")
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            center.post(name: name, object: nil)
            precondition(controller.status == "Waiting for the display.")
            precondition(overlayCount() == 0)
            center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
            center.post(name: NSWorkspace.didWakeNotification, object: nil)
            precondition(controller.status != "Waiting for the display.")
        }

        controller.enabled = false
        precondition(controller.status == "XDR boost is off.")
        precondition(overlayCount() == 0)
        controller.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        print("Inactive startup, sleep/session pause, resume, and overlay cleanup checks passed.")
    }

    private static func overlayCount() -> Int {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == getpid() &&
            (($0[kCGWindowLayer as String] as? NSNumber)?.int32Value ?? 0) >= CGShieldingWindowLevel()
        }.count
    }
}
