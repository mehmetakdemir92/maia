//
//  WordProgress.swift
//  maia
//
//  Created by Mehmet Akdemir on 26.01.2026.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Represents the spaced repetition progress for a single word
struct WordProgress: Identifiable, Codable, Equatable {
    let wordId: UUID
    var ease: Double // Default 2.5, min 1.3, max 3.5
    var intervalDays: Int // Default 0
    var repetitions: Int // Consecutive successful reviews (q >= 3)
    var nextDueAt: Date
    
    var id: UUID { wordId }
    
    init(wordId: UUID, ease: Double = 2.5, intervalDays: Int = 0, repetitions: Int = 0, nextDueAt: Date = Date()) {
        self.wordId = wordId
        self.ease = max(1.3, min(3.5, ease)) // Clamp between 1.3 and 3.5
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.nextDueAt = nextDueAt
    }
}

/// SM-2 spaced repetition algorithm implementation
class SpacedRepetitionManager {
    private let maxEase: Double = 3.5
    private let minEase: Double = 1.3
    
    /// Maps correct count (0..10) to quality grade q (0..5)
    /// - Parameters:
    ///   - correct: Number of correct answers
    ///   - total: Total number of questions asked
    /// - Returns: Quality grade (0-5)
    func gradeFromCount(correct: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        
        // For full 10-question sessions, use the mapping from requirements
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
            } else { // correct == 10
                return 5
            }
        }
        
        // For adaptive length (early stop or partial sessions), use accuracy ratio
        let accuracy = Double(correct) / Double(total)
        
        if accuracy == 1.0 && total >= 3 {
            return 5 // Perfect score with at least 3 questions
        } else if accuracy >= 0.8 {
            return 4 // 80-99% accuracy
        } else if accuracy >= 0.67 {
            return 3 // 67-79% accuracy
        } else if accuracy >= 0.5 {
            return 2 // 50-66% accuracy
        } else if accuracy >= 0.3 {
            return 1 // 30-49% accuracy
        } else {
            return 0 // <30% accuracy
        }
    }
    
    /// Updates word progress using SM-2 algorithm
    /// - Parameters:
    ///   - progress: Current word progress
    ///   - quality: Quality grade (0-5)
    ///   - now: Current date/time
    /// - Returns: Updated word progress
    func updateProgress(_ progress: WordProgress, quality: Int, now: Date = Date()) -> WordProgress {
        var updated = progress
        
        if quality < 3 {
            // Failed review
            updated.repetitions = 0
            updated.intervalDays = 1
            updated.ease = max(minEase, updated.ease - 0.2)
        } else {
            // Successful review (q >= 3)
            updated.repetitions += 1
            
            if updated.repetitions == 1 {
                updated.intervalDays = 1
            } else if updated.repetitions == 2 {
                updated.intervalDays = 6
            } else {
                // repetitions >= 3
                updated.intervalDays = Int(round(Double(updated.intervalDays) * updated.ease))
            }
            
            // Update ease based on quality
            if quality == 3 {
                // No change to ease
            } else if quality == 4 {
                updated.ease = min(maxEase, updated.ease + 0.05)
            } else if quality == 5 {
                updated.ease = min(maxEase, updated.ease + 0.10)
            }
        }
        
        // Ensure ease stays within bounds
        updated.ease = max(minEase, min(maxEase, updated.ease))
        
        // Calculate next due date
        updated.nextDueAt = scheduleNext(progress: updated, now: now)
        
        return updated
    }
    
    /// Calculates the next review date
    /// - Parameters:
    ///   - progress: Word progress with updated interval
    ///   - now: Current date/time
    /// - Returns: Next due date
    func scheduleNext(progress: WordProgress, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: progress.intervalDays, to: now) ?? now
    }
    
    /// Checks if a word is due for review
    /// - Parameters:
    ///   - progress: Word progress
    ///   - now: Current date/time
    /// - Returns: True if word is due for review
    func isDue(_ progress: WordProgress, now: Date = Date()) -> Bool {
        return progress.nextDueAt <= now
    }
}

/// Manages word progress storage and retrieval (SM-2 + Firestore)
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
                // Account switch: progress is stored in a global UserDefaults key today.
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
    
    /// Get or create progress for a word
    func getProgress(for wordId: UUID) -> WordProgress {
        if let existing = progressMap[wordId] {
            return existing
        }
        let newProgress = WordProgress(wordId: wordId)
        progressMap[wordId] = newProgress
        return newProgress
    }
    
    /// Update progress after a quiz session
    func updateProgress(for wordId: UUID, correct: Int, total: Int) {
        let quality = spacedRepetition.gradeFromCount(correct: correct, total: total)
        let currentProgress = getProgress(for: wordId)
        let updated = spacedRepetition.updateProgress(currentProgress, quality: quality)
        progressMap[wordId] = updated
        saveProgress()
        saveWordToFirestoreIfSignedIn(wordId: wordId, progress: updated)
    }
    
    /// Check if word is due for review
    func isDue(for wordId: UUID) -> Bool {
        let progress = getProgress(for: wordId)
        return spacedRepetition.isDue(progress)
    }
    
    /// Get next due date for a word
    func nextDueDate(for wordId: UUID) -> Date {
        return getProgress(for: wordId).nextDueAt
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
        
        // Decode as [String: WordProgress] then convert to [UUID: WordProgress]
        if let stringDict = try? JSONDecoder().decode([String: WordProgress].self, from: data) {
            progressMap = Dictionary(uniqueKeysWithValues: stringDict.compactMap { (key, value) in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            })
        } else {
            progressMap = [:]
        }

        // If we loaded from legacy storage, persist into the per-user key once.
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
            "nextDueAt": Timestamp(date: progress.nextDueAt)
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
                var nextDueAt = Date()
                if let ts = data["nextDueAt"] as? Timestamp {
                    nextDueAt = ts.dateValue()
                }
                let progress = WordProgress(wordId: wordId, ease: ease, intervalDays: intervalDays, repetitions: repetitions, nextDueAt: nextDueAt)
                self.progressMap[wordId] = progress
            }
            self.saveProgress()
        }
    }
    
    /// Reset progress for a word (for testing)
    func resetProgress(for wordId: UUID) {
        progressMap[wordId] = WordProgress(wordId: wordId)
        saveProgress()
    }
}

