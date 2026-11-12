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
            if enabled { samples.removeAll() }
            updateTimer()
        }
    }

    @Published var strength: Double = {
        let stored = BoostController.defaults.double(forKey: "BoostStrength")
        return (0.05...1).contains(stored) ? stored : 1
    }() {
        didSet { UserDefaults.standard.set(strength, forKey: "BoostStrength") }
    }

    @Published var method: BoostMethod = {
        let defaults = BoostController.defaults
        let stored = defaults.string(forKey: "BoostMethod") ?? defaults.string(forKey: "OverlayPlacement")
        if stored == "Live HDR" {
            defaults.set(BoostMethod.native.rawValue, forKey: "BoostMethod")
            return .native
        }
        return stored.flatMap(BoostMethod.init(rawValue:)) ?? .native
    }() {
        didSet {
            guard method != oldValue else { return }
            UserDefaults.standard.set(method.rawValue, forKey: "BoostMethod")
            samples.removeAll()
            stopTimer()
            closeOverlay()
            updateTimer()
        }
    }

    @Published private(set) var status = "XDR boost is off."
    private var overlay: XDROverlay?
    private var compositor: CompositorBoost?
    private var backlight: NativeBacklight?
    private var displayID: CGDirectDisplayID?
    private var timer: Timer?
    private var ramp = BoostRamp(model: BoostController.model)
    private var asleep = false
    private var sessionActive = true
    private var samples: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        updateTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimer()
        closeOverlay()
        _ = restoreBacklight()
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
            if restoreBacklight() { setStatus(enabled ? "Waiting for the display." : "XDR boost is off.") }
            return
        }

        if timer == nil {
            guard restoreBacklight() else { return }
            let interval = method == .direct ? 0.125 : 0.25
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
            if restoreBacklight() { setStatus("Waiting for a built-in XDR display.") }
            return
        }

        if method == .direct {
            tickBacklight(on: screen, display: display)
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

        if method == .native {
            tickCompositor(on: screen, display: display)
            return
        }

        if displayID != display { closeOverlay() }
        if overlay == nil {
            guard restoreBacklight() else { stopTimer(); return }
            overlay = XDROverlay(screen: screen, placement: method)
            displayID = display
        }
        guard let overlay else {
            stopTimer()
            setStatus("Metal could not start the brightness overlay.")
            return
        }

        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let factor = ramp.update(headroom: headroom, strength: strength)
        overlay.refresh(on: screen, factor: factor)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let visible = overlay.windows.filter { $0.occlusionState.contains(.visible) }.count
        record(String(format: "%.2f  EDR %.3f  gain %.3f  frames %ld  visible %ld/%ld",
                      timestamp, headroom, overlay.presentedFactor, overlay.framesSubmitted,
                      visible, overlay.windows.count))

        if overlay.presentedFactor > 1 {
            setStatus(overlay.placement == method ? "XDR boost is active." : "XDR boost is active using All Spaces.")
        } else {
            setStatus(overlay.framesSubmitted == 0 ? "Starting the brightness overlay." : "Waiting for HDR headroom.")
        }
    }

    private func tickCompositor(on screen: NSScreen, display: CGDirectDisplayID) {
        if compositor?.matches(screen: screen, display: display) != true {
            closeOverlay()
            guard restoreBacklight() else { stopTimer(); return }
            compositor = CompositorBoost(screen: screen, display: display)
        }
        guard let compositor else {
            stopTimer()
            setStatus("Native HDR is unavailable on this macOS version.")
            return
        }
        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let factor = ramp.update(headroom: headroom, strength: strength)
        compositor.refresh(on: screen, factor: factor)
        record(String(format: "%.2f  EDR %.3f  gain %.3f  filter updates %ld",
                      ProcessInfo.processInfo.systemUptime, headroom, factor, compositor.updates))
        let gain = (factor - 1).formatted(.percent.precision(.fractionLength(0)))
        setStatus(factor > 1 ? "Native HDR is active (\(gain) gain)." : "Waiting for HDR headroom.")
    }

    private func tickBacklight(on screen: NSScreen, display: CGDirectDisplayID) {
        do {
            if let backlight, backlight.display != display {
                closeOverlay()
                guard restoreBacklight() else { stopTimer(); return }
            }
            if backlight == nil { backlight = try NativeBacklight(display: display, bonus: ramp.maximumBonus) }
            if overlay == nil { overlay = XDROverlay(screen: screen, placement: .systemLayer, triggerOnly: true) }
            guard let overlay else { throw NativeBacklight.Failure("Metal could not start the HDR trigger.") }
            // The tiny surface keeps the display in EDR through compositor changes that reset the backlight.
            overlay.refresh(on: screen, factor: 1)
            guard overlay.framesSubmitted > 0, let backlight, let level = try backlight.update(strength: strength) else {
                setStatus("Preparing the display for direct brightness.")
                return
            }
            let timestamp = ProcessInfo.processInfo.systemUptime
            record(String(format: "%.2f  requested %.1f  register %.1f  cap %.1f nits  resets %ld",
                          timestamp, level.request, level.register, level.cap, backlight.resets))
            setStatus("Requested \(Int(level.request.rounded())) nits (cap \(Int(level.cap.rounded()))).")
        } catch {
            stopTimer()
            closeOverlay()
            if restoreBacklight() { setStatus(error.localizedDescription) }
        }
    }

    private func restoreBacklight() -> Bool {
        let display = backlight?.display ?? Self.builtInScreen(includeSleeping: true)?.1
        backlight = nil
        guard let display else { return true }
        do {
            try NativeBacklight.restorePending(display: display)
            return true
        } catch {
            setStatus(error.localizedDescription)
            return false
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func record(_ sample: String) {
        samples.append(sample)
        let capacity = method == .direct ? 160 : 80
        if samples.count > capacity { samples.removeFirst() }
    }

    private func closeOverlay() {
        compositor?.close()
        compositor = nil
        overlay?.close()
        overlay = nil
        displayID = nil
        ramp = BoostRamp(model: Self.model)
    }

    private func setStatus(_ message: String) {
        if status != message { status = message }
    }

    var diagnostics: String {
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        let actual = compositor != nil ? BoostMethod.native.rawValue : backlight != nil ? BoostMethod.direct.rawValue : overlay?.placement.rawValue ?? "Inactive"
        let header = "Sunbar · \(Self.model) · \(system)\nMethod: \(method.rawValue) (\(actual))\n\(status)"
        return ([header] + samples).joined(separator: "\n")
    }

    private static func builtInScreen(includeSleeping: Bool = false) -> (NSScreen, CGDirectDisplayID)? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let display = number.uint32Value
            if CGDisplayIsBuiltin(display) != 0, includeSleeping || CGDisplayIsAsleep(display) == 0 {
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
