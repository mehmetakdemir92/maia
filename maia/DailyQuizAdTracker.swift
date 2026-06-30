//
//  DailyQuizAdTracker.swift
//  maia
//

import Foundation

/// Daily completed quiz count (Istanbul calendar day). Used for one interstitial on first completion.
enum DailyQuizAdTracker {
    private static func dayISO() -> String {
        WordOfTheDayManager.calendarDayISO()
    }

    private static var completionsKey: String {
        "quizCompletionsCount.\(dayISO())"
    }

    static func completionsToday() -> Int {
        UserDefaults.standard.integer(forKey: completionsKey)
    }

    /// Call when a quiz finishes; returns the new daily total.
    @discardableResult
    static func recordCompletion() -> Int {
        let next = completionsToday() + 1
        UserDefaults.standard.set(next, forKey: completionsKey)
        return next
    }
}
