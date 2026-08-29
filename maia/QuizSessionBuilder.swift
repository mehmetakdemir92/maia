//
//  QuizSessionBuilder.swift
//  maia
//
// Composes ONE daily session out of the slot's new words plus whatever spaced
// repetition says is due.
//
//     session = [X new words] + [N words from the review queue]
//                fixed, authored   personal, algorithmic, ZERO new content cost
//
// Reviews reuse quiz items that were already written for those words, so the
// scheduler costs authoring nothing. New and review items are interleaved into
// a single run: the habit loop needs one unambiguous "done" moment, and two
// separate screens would split it.
//

import Foundation

/// One question in a session, tagged with the word it grades.
struct QuizSessionItem: Identifiable {
    let id: UUID
    let word: Word
    let preset: CurriculumQuiz
    let isReview: Bool

    var wordId: UUID { word.id }
}

@MainActor
enum QuizSessionBuilder {

    /// Hard ceiling on review items in one session.
    ///
    /// Steady-state review load is `newWordsPerDay × reviewsBeforeRetirement`.
    /// With the SM-2 parameters in SpacedRepetitionManager a word runs through
    /// intervals of 1, 6, 16, 42 and 113 days before crossing the 90-day
    /// retirement line — five reviews. At five new words a day that settles at
    /// ~25 review items, so the cap is set there deliberately: it must sit AT
    /// the steady state, not below it, or every day ends with leftovers and the
    /// backlog grows forever.
    ///
    /// Session length follows from this: 25 review x 1 question + 5 new x 2
    /// questions = 35 questions, a bit over three minutes. To make it shorter,
    /// lower X or `SpacedRepetitionManager.retirementIntervalDays` (dropping
    /// it to 40 retires after four reviews and takes review count to ~20) —
    /// do not simply lower this cap, which only hides the overflow.
    ///
    /// The cap still earns its keep for someone returning after a long absence:
    /// overflow stays due and arrives tomorrow, most overdue first.
    static let reviewCap = 25

    /// Questions asked per brand-new word in one session. One single-guess
    /// question made "you learned this" too weak a claim (25% chance right
    /// on a blind guess); two questions is enough to make it mean something
    /// without turning the session long. `WordProgressManager.updateProgress`
    /// is graded per word either way — see SpacedRepetitionManager.gradeFromCount
    /// for how a 2-question score maps to an SM-2 quality grade.
    static let questionsPerNewWord = 2

    /// Reviews already carry a pass history from earlier sessions via SM-2 —
    /// this exposure is at least their second — so one question is enough
    /// signal to grade them, and keeps the (much larger) review pool from
    /// doubling the whole session's length.
    static let questionsPerReviewWord = 1

    static func build(
        newWords: [Word],
        reviewCandidates: [Word],
        progress: WordProgressManager,
        language: LearningLanguage = .current,
        now: Date = Date(),
        seed: String
    ) -> [QuizSessionItem] {
        let newIds = Set(newWords.map(\.id))
        let due = progress
            .dueWords(from: reviewCandidates.filter { !newIds.contains($0.id) }, now: now)
            .prefix(reviewCap)

        var items: [QuizSessionItem] = []
        for word in newWords {
            items.append(contentsOf: makeItems(
                for: word, isReview: false, questionCount: questionsPerNewWord,
                progress: progress, language: language
            ))
        }
        for word in due {
            items.append(contentsOf: makeItems(
                for: word, isReview: true, questionCount: questionsPerReviewWord,
                progress: progress, language: language
            ))
        }

        var rng = SessionRandom(seed: stableSeed(for: seed))
        rng.shuffle(&items)
        return items
    }

    /// How many review items are waiting — for internal tuning only.
    ///
    /// Do NOT put this number in front of the learner. A visible backlog counter
    /// is what makes people abandon a review app; show "today: N questions" instead.
    static func pendingReviewCount(
        reviewCandidates: [Word],
        progress: WordProgressManager,
        now: Date = Date()
    ) -> Int {
        progress.dueWords(from: reviewCandidates, now: now).count
    }

    // MARK: - Item selection

    /// Picks an authored item the learner has not answered for this word yet,
    /// cycling once every item has been used. First exposure gets item 0, the
    /// first review gets item 1, and so on — so a review tests the word rather
    /// than a memorized question.
    private static func makeItems(
        for word: Word,
        isReview: Bool,
        questionCount: Int,
        progress: WordProgressManager,
        language: LearningLanguage
    ) -> [QuizSessionItem] {
        guard let presets = CurriculumService.curatedQuiz(forWord: word.word, language: language),
              !presets.isEmpty else {
            return []
        }
        let offset = progress.exposureCount(for: word.id)
        var items: [QuizSessionItem] = []
        for step in 0..<max(1, questionCount) {
            let preset = presets[(offset + step) % presets.count]
            items.append(
                QuizSessionItem(
                    id: UUID.stable(from: "\(word.id.uuidString)|\(offset + step)"),
                    word: word,
                    preset: preset,
                    isReview: isReview
                )
            )
        }
        return items
    }

    // MARK: - Deterministic shuffle

    private static func stableSeed(for text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    /// Same xorshift as QuizManager: order stays stable across app restarts, so
    /// backgrounding mid-session does not reshuffle the questions.
    private struct SessionRandom {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func next() -> UInt64 {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2685821657736338717
        }

        mutating func int(upperBound: Int) -> Int {
            guard upperBound > 0 else { return 0 }
            return Int(next() % UInt64(upperBound))
        }

        mutating func shuffle<T>(_ array: inout [T]) {
            guard array.count > 1 else { return }
            for i in stride(from: array.count - 1, through: 1, by: -1) {
                let j = int(upperBound: i + 1)
                if i != j { array.swapAt(i, j) }
            }
        }
    }
}
