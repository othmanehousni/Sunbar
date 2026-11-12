// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import CoreGraphics

@main
struct BoostChecks {
    static func main() {
        var ramp = BoostRamp(model: "MacBookPro18,3")
        precondition(ramp.update(headroom: 1, strength: 1) == 1)
        for _ in 0..<20 { _ = ramp.update(headroom: 3.2, strength: 1) }
        precondition(abs(ramp.factor - 1.58) < 0.00001)

        // A Space transition must not tear down the boost during a short loss of headroom.
        for _ in 0..<4 { precondition(ramp.update(headroom: 1, strength: 1) == 1.58) }
        precondition(ramp.update(headroom: 3.2, strength: 1) == 1.58)
        for _ in 0..<5 { _ = ramp.update(headroom: 1, strength: 1) }
        precondition(ramp.factor == 1)

        var modern = BoostRamp(model: "Mac16,1")
        for _ in 0..<20 { _ = modern.update(headroom: 2.66, strength: 1) }
        precondition(abs(modern.factor - 1.48) < 0.00001)
        precondition(modern.update(headroom: 1.1, strength: 1) <= 1.1)

        precondition(BoostRamp.sRGBMultiplier(for: 1) == 1)
        precondition(abs(BoostRamp.sRGBMultiplier(for: 1.2) - 1.0832683) < 0.000001)
        precondition(abs(BoostRamp.sRGBMultiplier(for: 1.58) - 1.2215160) < 0.000001)

        let screen = CGRect(x: -1512, y: 24, width: 1512, height: 981)
        let frames = OverlayGeometry.frames(for: screen)
        precondition(frames.count == 3)
        precondition(frames[0].union(frames[1]) == screen)
        precondition(frames[0].maxY == frames[1].minY)
        precondition(frames[0].height.rounded(.down) == frames[0].height)
        precondition(frames[2] == CGRect(x: -1, y: 24, width: 1, height: 1))
        precondition(OverlayGeometry.frames(for: screen, triggerOnly: true) == [frames[2]])

        let backlight = BacklightRange(sdrLimit: 500, panelLimit: 1600, bonus: 0.58)
        precondition(backlight?.request(strength: 0, activeLimit: 1600) == 500)
        precondition(abs((backlight?.request(strength: 1, activeLimit: 1600) ?? 0) - 790) < 0.001)
        precondition(backlight?.request(strength: 1, activeLimit: 500) == nil)
        precondition(backlight?.request(strength: 1, activeLimit: 650) == 650)
        precondition(BacklightRange(sdrLimit: 500, panelLimit: 500, bonus: 0.58) == nil)
        precondition(BacklightRange(sdrLimit: 600, panelLimit: 850, bonus: 0.48)?.request(strength: 1.2, activeLimit: 1600) == 850)
        print("Boost ramp, compositor gain, overlay geometry and backlight range checks passed.")
    }
}
