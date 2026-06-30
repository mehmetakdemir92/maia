//
//  StreakManager.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

class StreakManager: ObservableObject {
    @Published var currentStreak: Int = 0
    @Published var completedDates: Set<String> = []
    
    private static let legacyCompletedDatesKey = "completedStreakDates"
    private let db = Firestore.firestore()
    private var lastKnownAuthUID: String?

    private func completedDatesStorageKey(forUserId uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return "completedStreakDates.\(uid)"
    }
    
    init() {
        lastKnownAuthUID = Auth.auth().currentUser?.uid
        loadStreakData()
        updateCurrentStreak()
        setupAuthListener()
        if let userId = Auth.auth().currentUser?.uid {
            syncFromFirestore(userId: userId)
        }
    }
    
    private func setupAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            let newUid = user?.uid
            if newUid == self.lastKnownAuthUID { return }
            let previousUid = self.lastKnownAuthUID
            self.lastKnownAuthUID = newUid

            if let uid = newUid {
                self.loadStreakData()
                self.updateCurrentStreak()
                self.syncFromFirestore(userId: uid)
            } else {
                // Signed out: streak dates are stored in a global UserDefaults key today.
                // Clear in-memory + persisted state so the next account doesn't inherit streaks.
                self.completedDates = []
                self.currentStreak = 0
                if let previousUid,
                   let key = self.completedDatesStorageKey(forUserId: previousUid) {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
    }
    
    func markDayCompleted() {
        markDayCompleted(Date())
    }

    func markDayCompleted(_ date: Date) {
        let day = getDateString(date)
        completedDates.insert(day)
        saveStreakData()
        updateCurrentStreak()
        saveToFirestoreIfSignedIn()
    }
    
    /// Removes today (or the given date) from the streak.
    func unmarkDayCompleted(_ date: Date) {
        let dateString = getDateString(date)
        completedDates.remove(dateString)
        saveStreakData()
        updateCurrentStreak()
        saveToFirestoreIfSignedIn()
    }
    
    func isDayCompleted(_ date: Date) -> Bool {
        let dateString = getDateString(date)
        return completedDates.contains(dateString)
    }
    
    func getStreakCount() -> Int {
        return currentStreak
    }
    
    /// Longest consecutive streak from completed days
    var maxStreak: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let sortedDates = completedDates.compactMap { formatter.date(from: $0) }.sorted()
        guard !sortedDates.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var maxRun = 1
        var currentRun = 1
        
        for i in 1..<sortedDates.count {
            let dayDiff = calendar.dateComponents([.day], from: sortedDates[i - 1], to: sortedDates[i]).day ?? 0
            if dayDiff == 1 {
                currentRun += 1
                maxRun = max(maxRun, currentRun)
            } else {
                currentRun = 1
            }
        }
        return maxRun
    }
    
    func refreshStreak() {
        updateCurrentStreak()
    }

    var canRecoverMissedYesterday: Bool {
        recoverableStreakGapDate() != nil
    }

    @discardableResult
    func recoverYesterdayIfEligible() -> Bool {
        guard let recoverDate = recoverableStreakGapDate() else {
            return false
        }
        markDayCompleted(recoverDate)
        return true
    }

    /// Day immediately before the current streak block.
    /// e.g. if 4-5 completed, returns 3.
    func recoverableStreakGapDate() -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let sortedCompleted = completedDates.compactMap { formatter.date(from: $0) }.sorted()
        guard var streakStart = sortedCompleted.last else { return nil }

        while true {
            guard let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: streakStart) else {
                break
            }
            if completedDates.contains(getDateString(previousDay)) {
                streakStart = previousDay
            } else {
                break
            }
        }

        guard let recoverable = Calendar.current.date(byAdding: .day, value: -1, to: streakStart) else {
            return nil
        }
        if completedDates.contains(getDateString(recoverable)) {
            return nil
        }
        return recoverable
    }
    
    private func updateCurrentStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var streak = 0
        var checkDate: Date
        
        // Start from today if completed, otherwise yesterday
        if completedDates.contains(getDateString(today)) {
            checkDate = today
        } else {
            // Start from yesterday when today is not completed
            // Resets tomorrow if today remains incomplete
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                checkDate = calendar.startOfDay(for: yesterday)
            } else {
                currentStreak = 0
                return
            }
        }
        
        // Count consecutive completed days backward from the anchor date
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
        guard let uid = Auth.auth().currentUser?.uid,
              let key = completedDatesStorageKey(forUserId: uid) else {
            completedDates = []
            return
        }

        if let dates = UserDefaults.standard.array(forKey: key) as? [String] {
            completedDates = Set(dates)
            return
        }

        // One-time migration from legacy global key -> per-user key
        if let legacy = UserDefaults.standard.array(forKey: Self.legacyCompletedDatesKey) as? [String] {
            completedDates = Set(legacy)
            UserDefaults.standard.set(legacy, forKey: key)
            UserDefaults.standard.removeObject(forKey: Self.legacyCompletedDatesKey)
        }
    }
    
    private func saveStreakData() {
        guard let uid = Auth.auth().currentUser?.uid,
              let key = completedDatesStorageKey(forUserId: uid) else { return }
        UserDefaults.standard.set(Array(completedDates), forKey: key)
    }
    
    private func saveToFirestoreIfSignedIn() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(userId).collection("appData").document("streak")
        ref.setData([
            "completedDates": Array(completedDates),
            "currentStreak": currentStreak,
            "maxStreak": maxStreak
        ], merge: true) { error in
            if let error = error, (error as NSError).code != 7 {
                print("❌ Streak Firestore save error: \(error.localizedDescription)")
            }
        }
    }
    
    private func syncFromFirestore(userId: String) {
        let ref = db.collection("users").document(userId).collection("appData").document("streak")
        ref.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                if (error as NSError).code != 7 { print("❌ Streak Firestore load error: \(error.localizedDescription)") }
                return
            }
            guard let data = snapshot?.data(),
                  snapshot?.exists == true else {
                // New account / no streak doc yet: don't keep previous user's local streak cache.
                self.completedDates = []
                self.saveStreakData()
                self.updateCurrentStreak()
                return
            }
            guard let dates = data["completedDates"] as? [String] else {
                self.completedDates = []
                self.saveStreakData()
                self.updateCurrentStreak()
                return
            }
            self.completedDates = Set(dates)
            self.saveStreakData()
            self.updateCurrentStreak()
        }
    }
}
