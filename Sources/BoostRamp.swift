// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import Foundation

struct BoostRamp {
    static let headroomThreshold = 1.05

    let referenceHeadroom: Double
    let maximumBonus: Double

    private(set) var factor = 1.0
    private var missingFrames = 0

    static func sRGBMultiplier(for linearGain: Double) -> Float {
        Float(1.055 * pow(linearGain, 1.0 / 2.4) - 0.055)
    }

    init(model: String) {
        // The 2021 and 2023 panels have a 500-nit SDR reference. Newer panels use 600.
        let olderPanel = model.hasPrefix("MacBookPro18,") || ["Mac14,5", "Mac14,6", "Mac14,9", "Mac14,10"].contains(model)
        referenceHeadroom = olderPanel ? 3.2 : 2.66
        maximumBonus = olderPanel ? 0.58 : 0.48
    }

    mutating func update(headroom: Double, strength: Double) -> Double {
        guard strength.isFinite else {
            factor = 1
            return factor
        }
        guard headroom.isFinite, headroom > Self.headroomThreshold else {
            // Keep the last multiplier through short compositor handoffs.
            missingFrames = min(missingFrames + 1, 5)
            if missingFrames == 5 { factor = 1 }
            return factor
        }

        missingFrames = 0
        let amount = min(max(strength, 0), 1)
        let target = min(headroom, 1 + amount * maximumBonus * min(headroom / referenceHeadroom, 1))
        if target > factor {
            factor = min(target, factor + 0.04)
        } else {
            factor = max(target, factor - max(0.02, (factor - target) * 0.25))
        }
        factor = min(factor, headroom)
        return factor
    }
}
