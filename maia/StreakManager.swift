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
        let sortedDates = completedDates.compactMap { CurriculumStateManager.studyDayStart(fromISO: $0) }.sorted()
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

    /// Longest gap the rewarded-video bridge is allowed to close.
    static let maxBridgeGapLength = 3

    var canBridgeStreakGap: Bool {
        !bridgeableGapDates().isEmpty
    }

    /// Number of days the bridge would fill (0 when no bridge is available).
    var bridgeableGapLength: Int {
        bridgeableGapDates().count
    }

    /// Days a rewarded video would fill to join the current streak to the one
    /// that ended just before it, oldest first. Empty when no bridge applies.
    ///
    /// This is deliberately a *bridge*, never a free day. It requires a live
    /// streak on one side and an already-completed day on the other, so it can
    /// neither walk the streak backwards one ad at a time nor conjure a streak
    /// out of nothing. The gap itself is capped at `maxBridgeGapLength` days.
    func bridgeableGapDates() -> [Date] {
        Self.bridgeableGap(completedDayKeys: completedDates, asOf: Date())
    }

    /// Pure form of the rule, so it can be exercised without a Firebase session.
    static func bridgeableGap(
        completedDayKeys: Set<String>,
        asOf now: Date
    ) -> [Date] {
        let calendar = Calendar.current
        let key = { CurriculumStateManager.studyDayISO(for: $0) }
        guard let streakStart = currentStreakStart(
            completedDayKeys: completedDayKeys, asOf: now
        ) else { return [] }

        for gapLength in 1...maxBridgeGapLength {
            let gapDates: [Date] = (1...gapLength).compactMap {
                calendar.date(byAdding: .day, value: -$0, to: streakStart)
            }
            guard gapDates.count == gapLength,
                  let dayBeforeGap = calendar.date(
                    byAdding: .day, value: -(gapLength + 1), to: streakStart
                  )
            else { return [] }

            // A completed day inside the window means a shorter gap should
            // already have matched; nothing to bridge here.
            guard gapDates.allSatisfy({ !completedDayKeys.contains(key($0)) })
            else { return [] }

            // The far side must be a real completed day — that is the earlier
            // streak this bridge connects to.
            if completedDayKeys.contains(key(dayBeforeGap)) {
                return gapDates.reversed()
            }
        }

        return []
    }

    /// Fills the whole gap in one write and merges the two streaks.
    @discardableResult
    func bridgeStreakGapIfEligible() -> Bool {
        let gapDates = bridgeableGapDates()
        guard !gapDates.isEmpty else { return false }

        for date in gapDates {
            completedDates.insert(getDateString(date))
        }
        saveStreakData()
        updateCurrentStreak()
        saveToFirestoreIfSignedIn()
        return true
    }

    /// First day of the live streak block — nil when there is no live streak,
    /// which is what stops a video from starting a streak from nothing.
    static func currentStreakStart(
        completedDayKeys: Set<String>,
        asOf now: Date
    ) -> Date? {
        let calendar = Calendar.current
        let key = { CurriculumStateManager.studyDayISO(for: $0) }
        let today = CurriculumStateManager.studyDayStart(for: now)

        var start: Date
        if completedDayKeys.contains(key(today)) {
            start = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                  completedDayKeys.contains(key(yesterday)) {
            start = yesterday
        } else {
            return nil
        }

        while let previousDay = calendar.date(byAdding: .day, value: -1, to: start),
              completedDayKeys.contains(key(previousDay)) {
            start = previousDay
        }
        return start
    }
    
    private func updateCurrentStreak() {
        let calendar = Calendar.current
        // Anchored to the same study-day start the slot gate uses, not plain
        // midnight — stepping by whole days from here stays on that anchor,
        // so it must not be re-normalized with calendar.startOfDay below.
        let today = CurriculumStateManager.studyDayStart(for: Date())

        var streak = 0
        var checkDate: Date

        // Start from today if completed, otherwise yesterday
        if completedDates.contains(getDateString(today)) {
            checkDate = today
        } else {
            // Start from yesterday when today is not completed
            // Resets tomorrow if today remains incomplete
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                checkDate = yesterday
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
            checkDate = previousDay
        }

        currentStreak = streak
    }

    /// Same day boundary as the curriculum slot gate and diary: the learner's
    /// own timezone, shifted so a new day starts at `dayResetHour` instead of
    /// midnight.
    private func getDateString(_ date: Date) -> String {
        CurriculumStateManager.studyDayISO(for: date)
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
