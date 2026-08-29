//
//  CEFRLevelMapping.swift
//  maia
//
// Settings step (1–11) ↔ CEFR label. Nothing more.
//
// Band selection (preferredBands / substituteBands / fallbackBandPriority /
// isAcceptableCEFRDistribution) is gone: the curriculum is a single authored
// spine, so there is no per-level pick to make. Level now only chooses the
// entry point — see CurriculumPlacement.
//

import Foundation

enum CEFRLevelMapping {
    static let stepLabels: [String] = [
        "A1", "A1+", "A2", "A2+", "B1", "B1+", "B2", "B2+", "C1", "C1+", "C2"
    ]

    static func normalizedStep(_ userLevel: Int) -> Int {
        min(max(userLevel, 1), stepLabels.count)
    }

    static func label(for userLevel: Int) -> String {
        let step = normalizedStep(userLevel)
        return stepLabels[step - 1]
    }
}
