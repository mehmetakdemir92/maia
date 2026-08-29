//
//  WordProgress.swift
//  maia
//
//  Created by Mehmet Akdemir on 26.01.2026.
//
// SM-2 spaced repetition. In the slot curriculum this is no longer a side
// feature: the daily session is X new words plus whatever this scheduler says
// is due, so the numbers here decide how long a session runs.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Spaced repetition progress for a single word.
struct WordProgress: Identifiable, Codable, Equatable {
    let wordId: UUID
    var ease: Double        // Default 2.5, min 1.3, max 3.5
    var intervalDays: Int   // Default 0
    var repetitions: Int    // Consecutive successful reviews (q >= 3)
    var nextDueAt: Date
    /// Times this word has been failed. Drives leech detection.
    var lapses: Int
    /// Retired words are never scheduled again — this is what keeps the daily
    /// review queue bounded once the learner is hundreds of slots deep.
    var retired: Bool

    var id: UUID { wordId }

    init(
        wordId: UUID,
        ease: Double = 2.5,
        intervalDays: Int = 0,
        repetitions: Int = 0,
        nextDueAt: Date = Date(),
        lapses: Int = 0,
        retired: Bool = false
    ) {
        self.wordId = wordId
        self.ease = max(1.3, min(3.5, ease))
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.nextDueAt = nextDueAt
        self.lapses = lapses
        self.retired = retired
    }

    /// Tolerates records written before `lapses` / `retired` existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wordId = try container.decode(UUID.self, forKey: .wordId)
        ease = try container.decodeIfPresent(Double.self, forKey: .ease) ?? 2.5
        intervalDays = try container.decodeIfPresent(Int.self, forKey: .intervalDays) ?? 0
        repetitions = try container.decodeIfPresent(Int.self, forKey: .repetitions) ?? 0
        nextDueAt = try container.decodeIfPresent(Date.self, forKey: .nextDueAt) ?? Date()
        lapses = try container.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        retired = try container.decodeIfPresent(Bool.self, forKey: .retired) ?? false
    }

    /// 1-5, mirroring the SM-2 interval ladder (1 -> 6 -> 16 -> 42 -> 113 days,
    /// see SpacedRepetitionManager.updateProgress): each successful review
    /// advances a level, a lapse resets `repetitions` to 0 and drops back to 1.
    /// Retired words are always 5 even if `repetitions` undercounts them.
    var masteryLevel: Int {
        retired ? 5 : min(max(repetitions + 1, 1), 5)
    }
}

/// SM-2, tuned for one session per day.
class SpacedRepetitionManager {
    private let maxEase: Double = 3.5
    private let minEase: Double = 1.3

    /// Interval at which a word stops being scheduled.
    ///
    /// This is the knob that sets the steady-state review load. The interval
    /// ladder here runs 1 → 6 → 16 → 42 → 113 days, so a 90-day threshold means
    /// five reviews per word; at five new words a day that is ~25 review items
    /// daily (see QuizSessionBuilder.reviewCap). Lowering it to 40 retires after
    /// four reviews and cuts the daily session by about a fifth, at some cost to
    /// long-term retention.
    static let retirementIntervalDays = 90

    /// A word failed this many times is a leech: it is eating session time
    /// without sticking, and should be surfaced or rested rather than repeated.
    static let leechThreshold = 6

    /// Maps a word's score inside a session to an SM-2 quality grade (0–5).
    func gradeFromCount(correct: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }

        // 1-2 question grading is the DEFAULT path in the slot session: a new
        // word gets `QuizSessionBuilder.questionsPerNewWord` questions, a
        // review gets `questionsPerReviewWord`. A full miss on a sample this
        // small must not be graded q=0 — that drops ease by 0.2 every time,
        // and after a few misses the word is pinned at ease 1.3 in a
        // permanent one-day loop (the classic leech spiral). q=2 still counts
        // as a failure and resets the interval, without wrecking the ease
        // factor. (A partial miss, e.g. 1/2, already lands on q=2 via the
        // accuracy branch below on its own — this only needs to catch 0/2.)
        if total <= 2 {
            return correct == total ? 4 : 2
        }

        if total == 10 {
            if correct <= 2 {
                return 0
            } else if correct >= 3 && correct <= 4 {
                return 1
            } else if correct >= 5 && correct <= 6 {
                return 2
            } else if correct >= 7 && correct <= 8 {
                return 3
            } else if correct == 9 {
                return 4
            } else {
                return 5
            }
        }

        let accuracy = Double(correct) / Double(total)

        if accuracy == 1.0 && total >= 3 {
            return 5
        } else if accuracy >= 0.8 {
            return 4
        // Two thirds, written as the fraction rather than 0.67: the canonical
        // case here is 2 of 3 correct, and Double(2)/Double(3) is
        // 0.6666666666666666 — just under a literal 0.67, so that spelling
        // graded a 2/3 session as q=2 (a failure that resets the interval)
        // instead of q=3 (a pass). Dividing the same way on both sides makes
        // the comparison exact.
        } else if accuracy >= 2.0 / 3.0 {
            return 3
        } else if accuracy >= 0.5 {
            return 2
        } else if accuracy >= 0.3 {
            return 1
        } else {
            return 0
        }
    }

    func updateProgress(_ progress: WordProgress, quality: Int, now: Date = Date()) -> WordProgress {
        var updated = progress

        if quality < 3 {
            updated.repetitions = 0
            updated.intervalDays = 1
            updated.ease = max(minEase, updated.ease - 0.2)
            updated.lapses += 1
        } else {
            updated.repetitions += 1

            if updated.repetitions == 1 {
                updated.intervalDays = 1
            } else if updated.repetitions == 2 {
                updated.intervalDays = 6
            } else {
                updated.intervalDays = Int(round(Double(updated.intervalDays) * updated.ease))
            }

            if quality == 4 {
                updated.ease = min(maxEase, updated.ease + 0.05)
            } else if quality == 5 {
                updated.ease = min(maxEase, updated.ease + 0.10)
            }
        }

        updated.ease = max(minEase, min(maxEase, updated.ease))
        updated.nextDueAt = scheduleNext(progress: updated, now: now)

        // Learned for good: stop scheduling so the queue cannot grow forever.
        if updated.intervalDays >= Self.retirementIntervalDays {
            updated.retired = true
        }

        return updated
    }

    func scheduleNext(progress: WordProgress, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: progress.intervalDays, to: now) ?? now
    }

    func isDue(_ progress: WordProgress, now: Date = Date()) -> Bool {
        guard !progress.retired else { return false }
        return progress.nextDueAt <= now
    }

    func isLeech(_ progress: WordProgress) -> Bool {
        progress.lapses >= Self.leechThreshold
    }
}

/// Stores word progress (UserDefaults + Firestore) and answers "what is due".
class WordProgressManager: ObservableObject {
    @Published var progressMap: [UUID: WordProgress] = [:]

    private let spacedRepetition = SpacedRepetitionManager()
    private static let legacyProgressKey = "wordProgressMap"
    private let db = Firestore.firestore()
    private var lastObservedAuthUID: String?

    private func progressStorageKey(forUserId uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return "wordProgressMap.\(uid)"
    }

    init() {
        loadProgress()
        lastObservedAuthUID = Auth.auth().currentUser?.uid
        setupAuthListener()
        if let userId = Auth.auth().currentUser?.uid {
            syncFromFirestore(userId: userId)
        }
    }

    private func setupAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            let uid = user?.uid
            if uid == self.lastObservedAuthUID { return }
            let previous = self.lastObservedAuthUID
            self.lastObservedAuthUID = uid

            if let uid {
                if previous != nil {
                    self.progressMap = [:]
                    if let prev = previous, let oldKey = self.progressStorageKey(forUserId: prev) {
                        UserDefaults.standard.removeObject(forKey: oldKey)
                    }
                    UserDefaults.standard.removeObject(forKey: Self.legacyProgressKey)
                }
                self.loadProgress()
                self.syncFromFirestore(userId: uid)
            } else {
                self.progressMap = [:]
                if let prev = previous, let oldKey = self.progressStorageKey(forUserId: prev) {
                    UserDefaults.standard.removeObject(forKey: oldKey)
                }
                UserDefaults.standard.removeObject(forKey: Self.legacyProgressKey)
            }
        }
    }

    /// Get or create progress for a word.
    func getProgress(for wordId: UUID) -> WordProgress {
        if let existing = progressMap[wordId] {
            return existing
        }
        let newProgress = WordProgress(wordId: wordId)
        progressMap[wordId] = newProgress
        return newProgress
    }

    /// Has this word ever been studied? Used to tell new words from reviews.
    func hasSeen(_ wordId: UUID) -> Bool {
        guard let progress = progressMap[wordId] else { return false }
        return progress.repetitions > 0 || progress.lapses > 0
    }

    /// Total answered exposures — picks which authored quiz item to show next,
    /// so a review tests the word rather than a remembered question.
    func exposureCount(for wordId: UUID) -> Int {
        guard let progress = progressMap[wordId] else { return 0 }
        return progress.repetitions + progress.lapses
    }

    /// Update progress after a session. `total` is the number of questions that
    /// belonged to THIS word, not the size of the whole session.
    /// `now` should be a trusted timestamp (see `CurriculumStateManager.trustedNow()`)
    /// wherever the caller has one — the device clock can be pushed forward to
    /// bank a bogus `nextDueAt` far in the future, or back to make everything
    /// look due again.
    func updateProgress(for wordId: UUID, correct: Int, total: Int, now: Date = Date()) {
        let quality = spacedRepetition.gradeFromCount(correct: correct, total: total)
        let currentProgress = getProgress(for: wordId)
        let updated = spacedRepetition.updateProgress(currentProgress, quality: quality, now: now)
        progressMap[wordId] = updated
        saveProgress()
        saveWordToFirestoreIfSignedIn(wordId: wordId, progress: updated)
    }

    func isDue(for wordId: UUID) -> Bool {
        let progress = getProgress(for: wordId)
        return spacedRepetition.isDue(progress)
    }

    func isLeech(_ wordId: UUID) -> Bool {
        spacedRepetition.isLeech(getProgress(for: wordId))
    }

    func nextDueDate(for wordId: UUID) -> Date {
        return getProgress(for: wordId).nextDueAt
    }

    /// Due words from a candidate pool, most overdue first. Leeches are dropped:
    /// repeating a word that has failed six times spends session time badly.
    func dueWords(from candidates: [Word], now: Date = Date()) -> [Word] {
        candidates
            .filter { word in
                let progress = getProgress(for: word.id)
                guard spacedRepetition.isDue(progress, now: now) else { return false }
                return !spacedRepetition.isLeech(progress)
            }
            .sorted { getProgress(for: $0.id).nextDueAt < getProgress(for: $1.id).nextDueAt }
    }

    private func loadProgress() {
        guard let uid = Auth.auth().currentUser?.uid,
              let key = progressStorageKey(forUserId: uid) else {
            progressMap = [:]
            return
        }

        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: key) ?? defaults.data(forKey: Self.legacyProgressKey)
        guard let data else {
            progressMap = [:]
            return
        }

        if let stringDict = try? JSONDecoder().decode([String: WordProgress].self, from: data) {
            progressMap = Dictionary(uniqueKeysWithValues: stringDict.compactMap { (key, value) in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
        } else {
            progressMap = [:]
        }

        if defaults.data(forKey: key) == nil, defaults.data(forKey: Self.legacyProgressKey) != nil {
            saveProgress()
            defaults.removeObject(forKey: Self.legacyProgressKey)
        }
    }

    private func saveProgress() {
        guard let uid = Auth.auth().currentUser?.uid,
              let key = progressStorageKey(forUserId: uid) else { return }
        let stringDict = Dictionary(uniqueKeysWithValues: progressMap.map { (key, value) in
            (key.uuidString, value)
        })
        guard let encoded = try? JSONEncoder().encode(stringDict) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    private func saveWordToFirestoreIfSignedIn(wordId: UUID, progress: WordProgress) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(userId).collection("wordProgress").document(wordId.uuidString)
        ref.setData([
            "ease": progress.ease,
            "intervalDays": progress.intervalDays,
            "repetitions": progress.repetitions,
            "nextDueAt": Timestamp(date: progress.nextDueAt),
            "lapses": progress.lapses,
            "retired": progress.retired
        ], merge: true) { error in
            if let error = error, (error as NSError).code != 7 {
                print("❌ WordProgress Firestore save error: \(error.localizedDescription)")
            }
        }
    }

    private func syncFromFirestore(userId: String) {
        let ref = db.collection("users").document(userId).collection("wordProgress")
        ref.getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                if (error as NSError).code != 7 { print("❌ WordProgress Firestore load error: \(error.localizedDescription)") }
                return
            }
            guard let documents = snapshot?.documents else { return }
            if documents.isEmpty {
                self.progressMap = [:]
                self.saveProgress()
                return
            }
            for doc in documents {
                guard let wordId = UUID(uuidString: doc.documentID) else { continue }
                let data = doc.data()
                let ease = data["ease"] as? Double ?? 2.5
                let intervalDays = data["intervalDays"] as? Int ?? 0
                let repetitions = data["repetitions"] as? Int ?? 0
                let lapses = data["lapses"] as? Int ?? 0
                let retired = data["retired"] as? Bool ?? false
                var nextDueAt = Date()
                if let ts = data["nextDueAt"] as? Timestamp {
                    nextDueAt = ts.dateValue()
                }
                let progress = WordProgress(
                    wordId: wordId,
                    ease: ease,
                    intervalDays: intervalDays,
                    repetitions: repetitions,
                    nextDueAt: nextDueAt,
                    lapses: lapses,
                    retired: retired
                )
                self.progressMap[wordId] = progress
            }
            self.saveProgress()
        }
    }

    /// Reset progress for a word (for testing).
    func resetProgress(for wordId: UUID) {
        progressMap[wordId] = WordProgress(wordId: wordId)
        saveProgress()
    }
}
