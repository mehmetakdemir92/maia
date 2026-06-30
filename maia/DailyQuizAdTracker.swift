//
//  DailyQuizAdTracker.swift
//  maia
//

import Foundation

/// Günlük tamamlanan quiz sayısı (İstanbul günü). İlk quiz bitişinde tek interstitial için kullanılır.
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

    /// Quiz bittiğinde çağır; yeni toplamı döner.
    @discardableResult
    static func recordCompletion() -> Int {
        let next = completionsToday() + 1
        UserDefaults.standard.set(next, forKey: completionsKey)
        return next
    }
}
