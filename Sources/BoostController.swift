// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import AppKit
import Combine

@MainActor
final class BoostController: NSObject, ObservableObject, NSApplicationDelegate {
    private static let defaults = UserDefaults.standard

    @Published var enabled = BoostController.defaults.bool(forKey: "BoostEnabled") {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: "BoostEnabled")
            updateTimer()
        }
    }

    @Published var strength: Double = {
        let stored = BoostController.defaults.double(forKey: "BoostStrength")
        return (0.05...1).contains(stored) ? stored : 1
    }() {
        didSet {
            guard strength != oldValue else { return }
            UserDefaults.standard.set(strength, forKey: "BoostStrength")
        }
    }

    @Published private(set) var status = "XDR boost is off."
    private var compositor: CompositorBoost?
    private var timer: Timer?
    private var ramp = BoostRamp(model: BoostController.model)
    private var asleep = false
    private var sessionActive = true

    func applicationWillFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimer()
        closeOverlay()
    }

    @objc private func willSleep(_ notification: Notification) {
        asleep = true
        updateTimer()
    }

    @objc private func didWake(_ notification: Notification) {
        asleep = false
        updateTimer()
    }

    @objc private func sessionResigned(_ notification: Notification) {
        sessionActive = false
        updateTimer()
    }

    @objc private func sessionActivated(_ notification: Notification) {
        sessionActive = true
        updateTimer()
    }

    private func updateTimer() {
        guard enabled, sessionActive, !asleep else {
            stopTimer()
            closeOverlay()
            setStatus(enabled ? "Waiting for the display." : "XDR boost is off.")
            return
        }

        if timer == nil {
            let interval = 0.25
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = interval * 0.16
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        tick()
    }

    private func tick() {
        guard let (screen, display) = Self.builtInScreen() else {
            closeOverlay()
            setStatus("Waiting for a built-in XDR display.")
            return
        }

        guard screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 2.05 else {
            closeOverlay()
            setStatus("Waiting for a built-in XDR display.")
            return
        }

        // High-level surfaces can interfere with system authorization windows.
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.AppStore"
            || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.SecurityAgent").isEmpty {
            closeOverlay()
            setStatus("Paused for system authorization.")
            return
        }

        tickCompositor(on: screen, display: display)
    }

    private func tickCompositor(on screen: NSScreen, display: CGDirectDisplayID) {
        if compositor?.matches(screen: screen, display: display) != true {
            closeOverlay()
            compositor = CompositorBoost(screen: screen, display: display)
        }
        guard let compositor else {
            stopTimer()
            setStatus("Native HDR is unavailable on this macOS version.")
            return
        }
        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let factor = ramp.update(headroom: headroom, strength: strength)
        compositor.refresh(factor: factor)
        let gain = (factor - 1).formatted(.percent.precision(.fractionLength(0)))
        setStatus(factor > 1 ? "XDR boost is active (\(gain) gain)." : "Waiting for HDR headroom.")
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func closeOverlay() {
        compositor?.close()
        compositor = nil
        ramp = BoostRamp(model: Self.model)
    }

    private func setStatus(_ message: String) {
        if status != message { status = message }
    }

    private static func builtInScreen() -> (NSScreen, CGDirectDisplayID)? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let display = number.uint32Value
            if CGDisplayIsBuiltin(display) != 0, CGDisplayIsAsleep(display) == 0 {
                return (screen, display)
            }
        }
        return nil
    }

    private static let model: String = {
        var length = 0
        guard sysctlbyname("hw.model", nil, &length, nil, 0) == 0, length > 1 else { return "Unknown Mac" }
        var bytes = [UInt8](repeating: 0, count: length)
        guard sysctlbyname("hw.model", &bytes, &length, nil, 0) == 0 else { return "Unknown Mac" }
        return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }()
}
