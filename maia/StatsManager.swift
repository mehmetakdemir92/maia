//
//  StatsManager.swift
//  maia
//
// Quiz stats + streak rank (#1, #2).
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

class StatsManager: ObservableObject {
    @Published var totalQuizzesTaken: Int = 0
    @Published var totalPerfectQuizzes: Int = 0
    @Published var totalCorrectAnswers: Int = 0
    @Published var totalQuestionsAnswered: Int = 0
    /// Display rank by current streak: #1, #2, ...
    @Published var rankDisplay: String = "—"
    /// Display word rank by learned word count.
    @Published var wordRankDisplay: String = "—"

    // MARK: - Profile cards (Firestore panel overrides local counters)

    /// Document: users/{uid}/appData/profileDisplayStats
    /// Optional fields: quizCorrectAnswers, quizQuestionsAnswered, diaryWordsCount, exampleSentencesCount
    /// Falls back to UserDefaults / diary totals when fields are missing.
    @Published private(set) var profileQuizCorrectOverride: Int?
    @Published private(set) var profileQuizTotalOverride: Int?
    @Published private(set) var profileDiaryWordsOverride: Int?
    @Published private(set) var profileExampleSentencesOverride: Int?

    private static let legacyTotalQuizzesKey = "stats_totalQuizzesTaken"
    private static let legacyTotalPerfectKey = "stats_totalPerfectQuizzes"
    private static let legacyTotalCorrectKey = "stats_totalCorrectAnswers"
    private static let legacyTotalQuestionsKey = "stats_totalQuestionsAnswered"

    private func totalQuizzesKey(forUserId uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return "stats_totalQuizzesTaken.\(uid)"
    }

    private func totalCorrectKey(forUserId uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return "stats_totalCorrectAnswers.\(uid)"
    }

    private func totalPerfectKey(forUserId uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return "stats_totalPerfectQuizzes.\(uid)"
    }

    private func totalQuestionsKey(forUserId uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return "stats_totalQuestionsAnswered.\(uid)"
    }
    private let db = Firestore.firestore()
    private let scoresCollection = "scores"
    private var lastObservedAuthUID: String?
    private var lastWrittenRankStreak: Int?
    private var lastWrittenRankWordCount: Int?

    init() {
        loadStats()
        lastObservedAuthUID = Auth.auth().currentUser?.uid
        setupAuthListener()
        if let uid = Auth.auth().currentUser?.uid {
            loadStreakAndRank(userId: uid)
            fetchProfileDisplayStatsOnce(userId: uid)
        }
    }

    private func setupAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            let uid = user?.uid
            if uid == self.lastObservedAuthUID { return }
            let previous = self.lastObservedAuthUID
            self.lastObservedAuthUID = uid

            if let uid {
                // Cold start: keep whatever is already in UserDefaults for this install/session.
                // Account switch: quiz totals are global keys today, so reset to avoid leaking prior user.
                if previous != nil {
                    self.totalQuizzesTaken = 0
                    self.totalPerfectQuizzes = 0
                    self.totalCorrectAnswers = 0
                    self.totalQuestionsAnswered = 0
                }

                // Per-user keys: load persisted totals for this uid (falls back to legacy global keys once).
                self.loadStats()

                self.loadStreakAndRank(userId: uid)
                self.fetchProfileDisplayStatsOnce(userId: uid)
            } else {
                self.rankDisplay = "—"
                self.wordRankDisplay = "—"
                self.clearProfileDisplayOverrides()

                self.totalQuizzesTaken = 0
                self.totalPerfectQuizzes = 0
                self.totalCorrectAnswers = 0
                self.totalQuestionsAnswered = 0
                self.saveStats()
            }
        }
    }

    /// Quiz correct / total — panel override or on-device counters.
    var effectiveQuizCorrect: Int { profileQuizCorrectOverride ?? totalCorrectAnswers }
    var effectiveQuizTotal: Int { profileQuizTotalOverride ?? totalQuestionsAnswered }

    func displayedQuizAchievementPercent() -> String {
        let t = effectiveQuizTotal
        guard t > 0 else { return "0%" }
        let pct = Int(round(Double(effectiveQuizCorrect) / Double(t) * 100))
        return "\(pct)%"
    }

    func displayedWordsCount(diaryComputed: Int) -> Int {
        profileDiaryWordsOverride ?? diaryComputed
    }

    func displayedExampleSentencesCount(diaryComputed: Int) -> Int {
        profileExampleSentencesOverride ?? diaryComputed
    }

    private func clearProfileDisplayOverrides() {
        profileQuizCorrectOverride = nil
        profileQuizTotalOverride = nil
        profileDiaryWordsOverride = nil
        profileExampleSentencesOverride = nil
    }

    /// Panel stats rarely change; live listener adds CPU + Firestore noise.
    private func fetchProfileDisplayStatsOnce(userId: String) {
        let ref = db.collection("users").document(userId).collection("appData").document("profileDisplayStats")
        ref.getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if let error = error {
                let code = (error as NSError).code
                if code != 7 { print("⚠️ profileDisplayStats: \(error.localizedDescription)") }
                return
            }
            DispatchQueue.main.async {
                guard let data = snapshot?.data(), snapshot?.exists == true else {
                    self.clearProfileDisplayOverrides()
                    return
                }
                self.applyProfileDisplayOverrides(from: data)
            }
        }
    }

    private func applyProfileDisplayOverrides(from data: [String: Any]) {
        let quizCorrect = Self.optionalInt(from: data["quizCorrectAnswers"])
        let quizTotal = Self.optionalInt(from: data["quizQuestionsAnswered"])
        let diaryWords = Self.optionalInt(from: data["diaryWordsCount"])
        let examples = Self.optionalInt(from: data["exampleSentencesCount"])

        guard quizCorrect != profileQuizCorrectOverride
            || quizTotal != profileQuizTotalOverride
            || diaryWords != profileDiaryWordsOverride
            || examples != profileExampleSentencesOverride else {
            return
        }

        profileQuizCorrectOverride = quizCorrect
        profileQuizTotalOverride = quizTotal
        profileDiaryWordsOverride = diaryWords
        profileExampleSentencesOverride = examples
    }

    private static func optionalInt(from value: Any?) -> Int? {
        guard let value else { return nil }
        if let i = value as? Int { return i }
        if let i64 = value as? Int64 { return Int(i64) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    func recordQuizCompletion(correct: Int, total: Int) {
        totalQuizzesTaken += 1
        if total > 0 && correct == total {
            totalPerfectQuizzes += 1
        }
        totalCorrectAnswers += correct
        totalQuestionsAnswered += total
        saveStats()
    }

    var totalWrongAnswers: Int {
        totalQuestionsAnswered - totalCorrectAnswers
    }

    /// Updates rank from current streak.
    /// Legacy parameters retained; rank uses streak only.
    func updateScoreFrom(streak: Int, maxStreak: Int, wordCount: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        if lastWrittenRankStreak == streak, lastWrittenRankWordCount == wordCount { return }
        lastWrittenRankStreak = streak
        lastWrittenRankWordCount = wordCount

        let userRankRef = db.collection("users").document(uid).collection("appData").document("rank")
        let scoresRef = db.collection(scoresCollection).document(uid)
        userRankRef.setData([
            "currentStreak": streak,
            "wordCount": wordCount
        ], merge: true) { [weak self] error in
            if let error = error {
                print("❌ Rank Firestore save error: \(error.localizedDescription)")
                return
            }
            scoresRef.setData([
                "currentStreak": streak,
                "wordCount": wordCount
            ], merge: true) { [weak self] err in
                if let err = err {
                    print("❌ Scores Firestore save error: \(err.localizedDescription)")
                }
                self?.updateRankDisplay(myStreak: streak)
                self?.updateWordRankDisplay(myWordCount: wordCount)
            }
        }
    }

    /// Loads current streak from Firestore and computes rank.
    private func loadStreakAndRank(userId: String) {
        let ref = db.collection("users").document(userId).collection("appData").document("rank")
        ref.getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error, (error as NSError).code != 7 {
                print("❌ Rank Firestore load error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.rankDisplay = "—" }
                return
            }
            let streak = (snapshot?.data()?["currentStreak"] as? NSNumber)?.intValue ?? 0
            self.updateRankDisplay(myStreak: streak)
            self.db.collection(self.scoresCollection).document(userId).getDocument { [weak self] scoresSnapshot, scoresError in
                guard let self = self else { return }
                if let scoresError = scoresError, (scoresError as NSError).code != 7 {
                    print("❌ Scores wordCount load error: \(scoresError.localizedDescription)")
                    DispatchQueue.main.async { self.wordRankDisplay = "—" }
                    return
                }
                let wordCount = (scoresSnapshot?.data()?["wordCount"] as? NSNumber)?.intValue ?? 0
                self.updateWordRankDisplay(myWordCount: wordCount)
            }
        }
    }

    /// Rank = count of users with higher streak in scores + 1.
    private func updateRankDisplay(myStreak: Int) {
        db.collection(scoresCollection)
            .whereField("currentStreak", isGreaterThan: myStreak)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ Scores rank query error: \(error.localizedDescription)")
                    DispatchQueue.main.async { self.rankDisplay = "—" }
                    return
                }
                let countHigher = snapshot?.documents.count ?? 0
                let rank = countHigher + 1
                DispatchQueue.main.async {
                    self.rankDisplay = "#\(rank)"
                }
            }
    }

    /// Word rank = count of users with higher wordCount + 1.
    private func updateWordRankDisplay(myWordCount: Int) {
        db.collection(scoresCollection)
            .whereField("wordCount", isGreaterThan: myWordCount)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ Scores word rank query error: \(error.localizedDescription)")
                    DispatchQueue.main.async { self.wordRankDisplay = "—" }
                    return
                }
                let countHigher = snapshot?.documents.count ?? 0
                let rank = countHigher + 1
                DispatchQueue.main.async {
                    self.wordRankDisplay = "#\(rank)"
                }
            }
    }

    private func loadStats() {
        guard let uid = Auth.auth().currentUser?.uid else {
            totalQuizzesTaken = 0
            totalPerfectQuizzes = 0
            totalCorrectAnswers = 0
            totalQuestionsAnswered = 0
            return
        }

        guard let qKey = totalQuizzesKey(forUserId: uid),
              let pKey = totalPerfectKey(forUserId: uid),
              let cKey = totalCorrectKey(forUserId: uid),
              let tKey = totalQuestionsKey(forUserId: uid) else {
            totalQuizzesTaken = 0
            totalPerfectQuizzes = 0
            totalCorrectAnswers = 0
            totalQuestionsAnswered = 0
            return
        }

        let defaults = UserDefaults.standard
        if defaults.object(forKey: qKey) != nil {
            totalQuizzesTaken = defaults.integer(forKey: qKey)
        } else {
            totalQuizzesTaken = defaults.integer(forKey: Self.legacyTotalQuizzesKey)
        }

        if defaults.object(forKey: cKey) != nil {
            totalCorrectAnswers = defaults.integer(forKey: cKey)
        } else {
            totalCorrectAnswers = defaults.integer(forKey: Self.legacyTotalCorrectKey)
        }

        if defaults.object(forKey: pKey) != nil {
            totalPerfectQuizzes = defaults.integer(forKey: pKey)
        } else {
            totalPerfectQuizzes = defaults.integer(forKey: Self.legacyTotalPerfectKey)
        }

        if defaults.object(forKey: tKey) != nil {
            totalQuestionsAnswered = defaults.integer(forKey: tKey)
        } else {
            totalQuestionsAnswered = defaults.integer(forKey: Self.legacyTotalQuestionsKey)
        }

        // One-time migration from legacy global keys -> per-user keys
        let migratedFromLegacy =
            (defaults.object(forKey: qKey) == nil && defaults.object(forKey: Self.legacyTotalQuizzesKey) != nil)
            || (defaults.object(forKey: pKey) == nil && defaults.object(forKey: Self.legacyTotalPerfectKey) != nil)
            || (defaults.object(forKey: cKey) == nil && defaults.object(forKey: Self.legacyTotalCorrectKey) != nil)
            || (defaults.object(forKey: tKey) == nil && defaults.object(forKey: Self.legacyTotalQuestionsKey) != nil)

        if migratedFromLegacy {
            saveStats()
            defaults.removeObject(forKey: Self.legacyTotalQuizzesKey)
            defaults.removeObject(forKey: Self.legacyTotalPerfectKey)
            defaults.removeObject(forKey: Self.legacyTotalCorrectKey)
            defaults.removeObject(forKey: Self.legacyTotalQuestionsKey)
        }
    }

    private func saveStats() {
        guard let uid = Auth.auth().currentUser?.uid,
              let qKey = totalQuizzesKey(forUserId: uid),
              let pKey = totalPerfectKey(forUserId: uid),
              let cKey = totalCorrectKey(forUserId: uid),
              let tKey = totalQuestionsKey(forUserId: uid) else { return }

        let defaults = UserDefaults.standard
        defaults.set(totalQuizzesTaken, forKey: qKey)
        defaults.set(totalPerfectQuizzes, forKey: pKey)
        defaults.set(totalCorrectAnswers, forKey: cKey)
        defaults.set(totalQuestionsAnswered, forKey: tKey)
    }
}
