// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import Foundation

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

        for invalid in [Double.nan, .infinity, -.infinity] {
            precondition(ramp.update(headroom: 3.2, strength: invalid) == 1)
        }
        for _ in 0..<20 { _ = ramp.update(headroom: 3.2, strength: 10) }
        precondition(abs(ramp.factor - 1.58) < 0.00001)
        for _ in 0..<40 { _ = ramp.update(headroom: 3.2, strength: -1) }
        precondition(ramp.factor == 1)
        for _ in 0..<20 { _ = ramp.update(headroom: 3.2, strength: 0.5) }
        precondition(abs(ramp.factor - 1.29) < 0.00001)
        for _ in 0..<5 { _ = ramp.update(headroom: .nan, strength: 1) }
        precondition(ramp.factor == 1)
        print("Boost ramp, compositor gain, and invalid-input checks passed.")
    }
}
