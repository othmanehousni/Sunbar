// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import AppKit
import Metal

@main
struct BackdropChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        guard MTLCreateSystemDefaultDevice() != nil, let screen = NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            print("Backdrop idle checks skipped: a graphical Metal display is required.")
            return
        }
        guard let boost = CompositorBoost(screen: screen, display: number.uint32Value) else {
            preconditionFailure("The live compositor could not start.")
        }
        let windows = NSApp.windows.filter { $0.isVisible && $0.level.rawValue >= CGShieldingWindowLevel() }
        precondition(windows.count == 2, "Expected one backdrop and one HDR trigger.")
        let window = windows.first { $0.frame.width > 1 }!
        let layer = window.contentView!.layer!
        precondition(NSStringFromClass(type(of: layer)) == "CABackdropLayer")

        // Leave the gain unchanged beyond the idle-flattening interval.
        for _ in 0..<12 {
            boost.refresh(factor: 1)
            try await Task.sleep(for: .milliseconds(250))
        }
        precondition(window.value(forKey: "shouldAutoFlattenLayerTree") as? Bool == false)
        precondition(window.value(forKey: "canHostLayersInWindowServer") as? Bool == true)
        precondition(window.isVisible && window.contentView?.layer === layer)
        precondition(layer.filters?.count == 1)
        boost.close()
        precondition(windows.allSatisfy { !$0.isVisible })
        print("Steady-gain backdrop, idle-flattening prevention, and cleanup checks passed.")
    }
}
