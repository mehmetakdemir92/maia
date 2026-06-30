//
//  DailyWordsService.swift
//  maia
//
// Daily words from a single source: maia/WordPacks/{yyyy-MM}.json.
// AI (Gemini) and Firestore write paths removed. Quiz questions and extra examples
// live in the same files. Diary correctSentence (the remaining AI feature)
// still runs via Functions; this service does not touch it.
//

import Foundation

@MainActor
final class DailyWordsService {

    // MARK: - Manual override (developer)
    /// Dev override: force a specific day's three lemmas from WordPack.
    /// Still selects words defined in WordPack; forces that day to these three lemmas.
    /// e.g. DailyWordsService.manualWordsByDate["2026-06-15"] = ["happy", "address", "anticipate"]
    static var manualWordsByDate: [String: [String]] = [:]

    // MARK: - Public API

    /// Three words for a date, selected from WordPack.
    /// Applies manual override when set (definition/sentences/quiz still from WordPack).
    func ensureDailyWords(date: String, category _: String, userLevel: Int) async throws -> [Word] {
        let words = Self.resolveWords(date: date, userLevel: userLevel)

        guard !words.isEmpty else {
            throw NSError(
                domain: "DailyWordsService",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: Self.missingPackErrorMessage(for: date)]
            )
        }
        guard words.count == 3 else {
            throw NSError(
                domain: "DailyWordsService",
                code: -11,
                userInfo: [NSLocalizedDescriptionKey: Self.partialPackErrorMessage(for: date, count: words.count)]
            )
        }

        DailyWordUsageStore.shared.markUsed(words: words.map(\.word), level: userLevel)

        let withAudio = await Self.attachPronunciations(to: words)
        return withAudio
    }

    /// Called on every Today load. WordPack example sentences already
    /// include the target word, so this is a no-op; signature kept for
    /// backward compatibility.
    func repairExampleSentencesIfNeeded(in words: [Word]) async -> [Word] {
        words
    }

    // MARK: - Word selection

    private static func resolveWords(date: String, userLevel: Int) -> [Word] {
        if let manual = manualWordsByDate[date], manual.count == 3,
           let resolved = wordsForManualOverride(date: date, userLevel: userLevel, lemmas: manual) {
            return resolved
        }
        return WordPackStore.shared.words(for: date, userLevel: userLevel)
    }

    private static func wordsForManualOverride(date: String, userLevel: Int, lemmas: [String]) -> [Word]? {
        let entries = WordPackStore.shared.entries(for: date)
        guard !entries.isEmpty else { return nil }
        let lookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.word.lowercased(), $0) })
        var resolved: [Word] = []
        for lemma in lemmas {
            guard let entry = lookup[lemma.lowercased()] else {
                print("⚠️ DailyWordsService.manualWordsByDate[\(date)]: '\(lemma)' WordPack'te yok.")
                return nil
            }
            resolved.append(entry.toWord())
        }
        _ = userLevel
        return resolved
    }

    // MARK: - Helpers (legacy API hooks)

    /// QuizManager: reads curated quizzes for a date/word pair.
    static func curatedQuiz(forWord word: String, date: String) -> [WordPackQuiz]? {
        WordPackStore.shared.quizQuestions(forWord: word, date: date)
    }

    /// TodayTabView: reads pre-written 2nd/3rd sentences for Generate More.
    static func extraExamples(forWord word: String, date: String) -> [String] {
        WordPackStore.shared.extraExampleSentences(forWord: word, date: date)
    }

    /// Legacy WordOfTheDayManager hook; same pool band check for CEFR compatibility.
    static func poolHasBand(_ band: String) -> Bool {
        let lowered = band.lowercased()
        return [
            "a1", "a2", "b1", "b2", "c1", "c2"
        ].contains(lowered)
    }

    /// WordOfTheDayManager: whether locally locked words are still valid.
    static func isUsableWordSet(_ words: [Word]) -> Bool {
        guard words.count == 3 else { return false }
        return !words.contains(where: hasPlaceholderContent)
            && words.allSatisfy(exampleIncludesHeadword)
    }

    /// WordOfTheDayManager.loadLockedWords hook; hash mismatch check for daily words.
    static func isFirestoreCacheStale(parsed _: [Word], date _: String, userLevel _: Int) -> Bool {
        false
    }

    static func exampleIncludesHeadword(_ word: Word) -> Bool {
        let lemma = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lemma.isEmpty else { return true }
        let example = word.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !example.isEmpty else { return false }

        let escaped = NSRegularExpression.escapedPattern(for: lemma)
        let options: NSString.CompareOptions = [.regularExpression, .caseInsensitive]
        if example.range(of: "\\b\(escaped)\\b", options: options) != nil { return true }

        let suffixes = ["s", "es", "ed", "ing", "er", "est", "ly", "d"]
        for suffix in suffixes {
            if example.range(of: "\\b\(escaped)\(suffix)\\b", options: options) != nil { return true }
        }
        return false
    }

    private static func hasPlaceholderContent(_ word: Word) -> Bool {
        let definition = word.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let example = word.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders = ["TODO", "FIXME", "<PLACEHOLDER>"]
        return placeholders.contains(where: { definition.contains($0) || example.contains($0) })
    }

    // MARK: - Pronunciation (Functions callable yerine cache + on-demand)

    private static func attachPronunciations(to words: [Word]) async -> [Word] {
        var updated = words
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, item) in words.enumerated() where item.pronunciationAudioURL == nil {
                group.addTask {
                    let url = await WordPronunciationService.shared.resolveAudioURL(for: item.word)
                    return (index, url)
                }
            }
            for await (index, url) in group {
                if let url {
                    updated[index] = updated[index].withPronunciationAudioURL(url)
                }
            }
        }
        return updated
    }

    // MARK: - Error messages

    private static func missingPackErrorMessage(for date: String) -> String {
        let monthKey = WordPackStore.monthKey(from: date) ?? date
        return String(
            format: String(localized: "Today's words aren't curated yet. Add maia/WordPacks/%@.json and rebuild."),
            monthKey
        )
    }

    private static func partialPackErrorMessage(for date: String, count: Int) -> String {
        String(
            format: String(localized: "Only %1$lld words are curated for %2$@. Need 3."),
            Int64(count),
            date
        )
    }

    // MARK: - Legacy compat (no-op)

    /// Legacy Firestore sync removed in this architecture; safe no-op if still called.
    static func syncUsedWordsFromFirestoreOnce(userLevel _: Int) async {}
}
