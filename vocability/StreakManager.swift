//
//  StreakManager.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import Foundation
import Combine

class StreakManager: ObservableObject {
    @Published var currentStreak: Int = 0
    @Published var completedDates: Set<String> = []
    
    private let completedDatesKey = "completedStreakDates"
    
    init() {
        loadStreakData()
        updateCurrentStreak()
    }
    
    func markDayCompleted() {
        let today = getDateString(Date())
        completedDates.insert(today)
        saveStreakData()
        updateCurrentStreak()
    }
    
    func isDayCompleted(_ date: Date) -> Bool {
        let dateString = getDateString(date)
        return completedDates.contains(dateString)
    }
    
    func getStreakCount() -> Int {
        return currentStreak
    }
    
    private func updateCurrentStreak() {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        
        while completedDates.contains(getDateString(checkDate)) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else {
                break
            }
            checkDate = calendar.startOfDay(for: previousDay)
        }
        
        currentStreak = streak
    }
    
    private func getDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func loadStreakData() {
        if let dates = UserDefaults.standard.array(forKey: completedDatesKey) as? [String] {
            completedDates = Set(dates)
        }
    }
    
    private func saveStreakData() {
        UserDefaults.standard.set(Array(completedDates), forKey: completedDatesKey)
    }
}
