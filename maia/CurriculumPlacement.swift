//
//  CurriculumPlacement.swift
//  maia
//
// Level handling for a single-spine curriculum. There is one word sequence for
// everyone; a learner's level decides only WHERE they enter it. This replaces
// the old per-level band selection (CEFRLevelMapping.preferredBands and friends).
//

import Foundation

enum CurriculumPlacement {

    /// The spine is authored from B1 upward. Settings step 5 is B1.
    static let spineFloorStep = 5

    /// Onboarding level (1–11) → 1-based entry slot.
    /// Steps below B1 start at slot 1: there is no easier content yet, and
    /// dropping them at a harder position would be worse than starting early.
    static func startSlot(forUserLevel userLevel: Int) -> Int {
        switch CEFRLevelMapping.normalizedStep(userLevel) {
        case 1...5: return 1    // A1 … B1
        case 6:     return 5    // B1+
        case 7:     return 11   // B2
        case 8:     return 16   // B2+
        case 9:     return 23   // C1
        case 10:    return 26   // C1+
        default:    return 30   // C2
        }
    }

    /// Entry slot clamped to what is actually authored, so a deep placement on a
    /// short spine lands on the last real slot instead of nowhere.
    static func startSlot(forUserLevel userLevel: Int, slotCount: Int) -> Int {
        guard slotCount > 0 else { return 1 }
        return min(max(1, startSlot(forUserLevel: userLevel)), slotCount)
    }

    /// True when the learner sits below the spine's floor. The UI should warn
    /// that the content will run hard rather than silently serving B1 words.
    static func isBelowSpineFloor(userLevel: Int) -> Bool {
        CEFRLevelMapping.normalizedStep(userLevel) < spineFloorStep
    }

    /// Human-readable placement, e.g. "B2 · 11. slottan başlıyor".
    static func placementSummary(forUserLevel userLevel: Int, slotCount: Int) -> String {
        let slot = startSlot(forUserLevel: userLevel, slotCount: slotCount)
        return "\(CEFRLevelMapping.label(for: userLevel)) · slot \(slot)"
    }
}
