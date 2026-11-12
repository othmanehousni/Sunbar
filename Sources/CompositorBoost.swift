// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import AppKit
import QuartzCore

@MainActor
final class CompositorBoost {
    private let display: CGDirectDisplayID
    private let frame: CGRect
    private let scale: CGFloat
    private let window: NSWindow
    private let space: PinnedSpace
    private let trigger: HDRTrigger
    private let filterType: NSObject.Type
    private var factor: Double?

    init?(screen: NSScreen, display: CGDirectDisplayID) {
        let makeFilter = NSSelectorFromString("filterWithType:")
        let makeLayer = NSSelectorFromString("layer")
        guard let colorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let filterType = NSClassFromString("CAFilter") as? NSObject.Type,
              filterType.responds(to: makeFilter),
              let filter = filterType.perform(makeFilter, with: "colorMatrix")?.takeUnretainedValue() as? NSObject,
              filter.responds(to: NSSelectorFromString("inputKeys")),
              let inputs = filter.value(forKey: "inputKeys") as? [String], inputs.contains("inputColorMatrix"),
              let layerType = NSClassFromString("CABackdropLayer") as? NSObject.Type,
              layerType.responds(to: makeLayer),
              let layer = layerType.perform(makeLayer)?.takeUnretainedValue() as? CALayer,
              ["setWindowServerAware:", "setAllowsInPlaceFiltering:", "setScale:", "setGroupName:"].allSatisfy({
                  layer.responds(to: NSSelectorFromString($0))
              }) else { return nil }

        frame = screen.frame
        scale = screen.backingScaleFactor
        self.display = display
        self.filterType = filterType

        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.canHide = false
        window.animationBehavior = .none
        window.colorSpace = NSColorSpace(cgColorSpace: colorSpace)
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.sharingType = .readOnly
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        window.setAccessibilityElement(false)

        layer.frame = CGRect(origin: .zero, size: frame.size)
        layer.contentsScale = scale
        layer.contentsFormat = .RGBA16Float
        layer.setValue(true, forKey: "windowServerAware")
        layer.setValue(false, forKey: "allowsInPlaceFiltering")
        layer.setValue(1, forKey: "scale")
        layer.setValue("io.github.othmanehousni.Sunbar.boost.\(display)", forKey: "groupName")
        let view = NSView(frame: layer.frame)
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        self.window = window

        guard let space = PinnedSpace(windows: [window]) else {
            window.close()
            return nil
        }
        self.space = space
        guard let trigger = HDRTrigger(screen: screen) else {
            space.close()
            window.close()
            return nil
        }
        self.trigger = trigger
        refresh(factor: 1)
        window.orderFrontRegardless()
    }

    func matches(screen: NSScreen, display: CGDirectDisplayID) -> Bool {
        self.display == display && frame == screen.frame && scale == screen.backingScaleFactor
    }

    func refresh(factor: Double) {
        if self.factor != factor {
            // Core Animation copies filter state when it is assigned to the layer.
            guard let filter = filterType.perform(NSSelectorFromString("filterWithType:"), with: "colorMatrix")?
                .takeUnretainedValue() as? NSObject else { return }
            // The matrix operates on encoded sRGB, so calibrate its multiplier to SDR white.
            let gain = BoostRamp.sRGBMultiplier(for: factor)
            // CAFilter's color matrix is four rows of five 32-bit floats.
            let matrix: [Float] = [
                gain, 0, 0, 0, 0,
                0, gain, 0, 0, 0,
                0, 0, gain, 0, 0,
                0, 0, 0, 1, 0,
            ]
            let value = matrix.withUnsafeBytes {
                NSValue(bytes: $0.baseAddress!, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            filter.setValue(value, forKey: "inputColorMatrix")
            window.contentView?.layer?.filters = [filter]
            CATransaction.commit()
            self.factor = factor
        }
        trigger.refresh()
    }

    func close() {
        window.orderOut(nil)
        trigger.close()
        space.close()
        window.close()
    }
}
