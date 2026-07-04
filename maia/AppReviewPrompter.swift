//
//  AppReviewPrompter.swift
//  maia
//
// Decides when to ask for an App Store rating. The actual sheet is the
// system one (SwiftUI requestReview); Apple caps it at 3 prompts/year,
// this gate just makes sure we only ask engaged users, rarely.
//

import Foundation

enum AppReviewPrompter {
    /// Ask only users with a real habit (3+ day streak = happiest moment).
    static let minimumStreak = 3
    static let minimumDaysBetweenPrompts = 60

    private static let lastPromptKey = "appReview.lastPromptDate"

    static func shouldPrompt(
        currentStreak: Int,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard currentStreak >= minimumStreak else { return false }
        guard let last = defaults.object(forKey: lastPromptKey) as? Date else { return true }
        let days = Calendar.current.dateComponents([.day], from: last, to: now).day ?? 0
        return days >= minimumDaysBetweenPrompts
    }

    static func recordPrompt(now: Date = Date(), defaults: UserDefaults = .standard) {
        defaults.set(now, forKey: lastPromptKey)
    }
}
