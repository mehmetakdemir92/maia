//
//  WordPack.swift
//  maia
//
// Loads monthly WordPack JSON files. Daily words come from
// maia/WordPacks/{yyyy-MM}.json instead of AI; single source of truth.
//

import Foundation

// MARK: - JSON Models

/// Monthly file root. Filename `2026-06.json`, contains month: "2026-06".
struct WordPack: Codable, Equatable {
    let month: String
    let days: [String: WordPackDay]
}

/// Curated words for a calendar day. Two words per CEFR band are suggested
/// but missing bands are tolerated because selection uses preferredBands.
struct WordPackDay: Codable, Equatable {
    let words: [WordPackWord]
}

struct WordPackWord: Codable, Equatable {
    let word: String
    let cefrLevel: String
    let definition: String
    /// Three example sentences. Free users see the first; Generate More reveals the rest.
    let examples: [String]
    /// Tam 3 quiz sorusu. Tipik: 1 definition + 2 blank.
    let quiz: [WordPackQuiz]
    let phonetic: String?
    let partOfSpeech: String?
    let domainTag: String?
    let registerTag: String?
    let frequencyBand: Int?
}

/// Quiz question. type is informational; QuizManager renders question/choices as-is.
struct WordPackQuiz: Codable, Equatable {
    let type: String
    let question: String
    let options: [String]
    let correctAnswerIndex: Int
}

// MARK: - Store

/// Reads WordPack JSON from the bundle and selects three words for a day
/// using CEFRLevelMapping.preferredBands(for:).
@MainActor
final class WordPackStore {
    static let shared = WordPackStore()

    private var cache: [String: WordPack] = [:]
    private var missingMonthsLogged = Set<String>()

    private init() {}

    // MARK: Public API

    /// Cached pack for the month, or nil if missing.
    func pack(forMonth monthKey: String) -> WordPack? {
        if let cached = cache[monthKey] { return cached }
        guard let pack = Self.loadPack(forMonth: monthKey) else {
            if !missingMonthsLogged.contains(monthKey) {
                missingMonthsLogged.insert(monthKey)
                print("⚠️ WordPack: \(monthKey).json bundle'da bulunamadı. " +
                      "`maia/WordPacks/\(monthKey).json` ekleyin (Xcode otomatik dahil eder).")
            }
            return nil
        }
        cache[monthKey] = pack
        return pack
    }

    /// All curated words for a day (12 suggested). Returns [] if day is missing.
    func entries(for date: String) -> [WordPackWord] {
        guard let monthKey = Self.monthKey(from: date) else { return [] }
        guard let pack = pack(forMonth: monthKey) else { return [] }
        return pack.days[date]?.words ?? []
    }

    /// Returns three Words for the user level. Missing bands are filled via
    /// CEFRLevelMapping.fallbackBandPriority; returns [] when empty.
    func words(for date: String, userLevel: Int) -> [Word] {
        let all = entries(for: date)
        guard !all.isEmpty else { return [] }
        let picked = Self.selectByPreferredBands(all, userLevel: userLevel, date: date)
        return picked.map { $0.toWord() }
    }

    /// QuizManager: word + date → three pre-written quiz questions.
    func quizQuestions(forWord word: String, date: String) -> [WordPackQuiz]? {
        let entries = entries(for: date)
        guard let entry = entries.first(where: { $0.word.lowercased() == word.lowercased() }) else {
            return nil
        }
        return entry.quiz
    }

    /// Generate More: reveals pre-written 2nd/3rd example sentences.
    func extraExampleSentences(forWord word: String, date: String) -> [String] {
        let entries = entries(for: date)
        guard let entry = entries.first(where: { $0.word.lowercased() == word.lowercased() }),
              entry.examples.count > 1 else {
            return []
        }
        return Array(entry.examples.dropFirst())
    }

    // MARK: Internals

    static func monthKey(from date: String) -> String? {
        let parts = date.split(separator: "-")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0])-\(parts[1])"
    }

    private static func loadPack(forMonth monthKey: String) -> WordPack? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: monthKey, withExtension: "json", subdirectory: "WordPacks"),
            Bundle.main.url(forResource: monthKey, withExtension: "json")
        ]
        for case let url? in candidates {
            if let pack = decode(at: url, monthKey: monthKey) {
                return pack
            }
        }
        return nil
    }

    private static func decode(at url: URL, monthKey: String) -> WordPack? {
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(WordPack.self, from: data)
            if decoded.month != monthKey {
                print("⚠️ WordPack: \(monthKey).json içindeki month=\(decoded.month) — dosya adı ile uyumsuz.")
            }
            return decoded
        } catch {
            print("⚠️ WordPack: \(url.lastPathComponent) parse hatası:", error)
            return nil
        }
    }

    /// Stable FNV-1a 64-bit for date + word (same as DailyWordsService).
    private static func stableScore(date: String, word: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in "\(date)|\(word.lowercased())".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    /// Select three words by preferredBands; stable hash tie-break within a band.
    /// Fill from fallbackBandPriority when a band is missing (e.g. no C1).
    static func selectByPreferredBands(
        _ all: [WordPackWord],
        userLevel: Int,
        date: String
    ) -> [WordPackWord] {
        let bands = CEFRLevelMapping.preferredBands(for: userLevel).map { $0.lowercased() }
        var picked: [WordPackWord] = []
        var usedKeys = Set<String>()

        func candidates(in band: String) -> [WordPackWord] {
            all.filter { entry in
                entry.cefrLevel.lowercased() == band
                    && !usedKeys.contains(entry.word.lowercased())
            }
        }

        func sortedByStableHash(_ items: [WordPackWord], salt: String) -> [WordPackWord] {
            items.sorted { lhs, rhs in
                let lScore = stableScore(date: "\(date)|\(salt)", word: lhs.word)
                let rScore = stableScore(date: "\(date)|\(salt)", word: rhs.word)
                if lScore != rScore { return lScore < rScore }
                return lhs.word.lowercased() < rhs.word.lowercased()
            }
        }

        for band in bands {
            let pool = sortedByStableHash(candidates(in: band), salt: "band-\(band)")
            if let first = pool.first {
                usedKeys.insert(first.word.lowercased())
                picked.append(first)
            }
        }

        if picked.count < 3 {
            for band in CEFRLevelMapping.fallbackBandPriority(for: userLevel) {
                if picked.count >= 3 { break }
                let pool = sortedByStableHash(candidates(in: band.lowercased()), salt: "fallback-\(band)")
                if let pick = pool.first {
                    usedKeys.insert(pick.word.lowercased())
                    picked.append(pick)
                }
            }
        }

        if picked.count < 3 {
            let remaining = all.filter { !usedKeys.contains($0.word.lowercased()) }
            for entry in sortedByStableHash(remaining, salt: "any") {
                if picked.count >= 3 { break }
                picked.append(entry)
                usedKeys.insert(entry.word.lowercased())
            }
        }

        let finalRanked = picked.sorted { lhs, rhs in
            let lScore = stableScore(date: date, word: lhs.word)
            let rScore = stableScore(date: date, word: rhs.word)
            if lScore != rScore { return lScore < rScore }
            return lhs.word.lowercased() < rhs.word.lowercased()
        }
        return Array(finalRanked.prefix(3))
    }
}

// MARK: - Word bridge

extension WordPackWord {
    func toWord() -> Word {
        let cleanedExamples = examples.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let primary = cleanedExamples.first ?? ""
        let second = cleanedExamples.indices.contains(1) ? cleanedExamples[1] : nil
        let third = cleanedExamples.indices.contains(2) ? cleanedExamples[2] : nil

        return Word(
            id: UUID.stable(from: word.lowercased()),
            word: word,
            definition: definition,
            exampleSentence: primary,
            phonetic: phonetic,
            pronunciationAudioURL: nil,
            exampleSentence2: second,
            exampleSentence3: third,
            cefrLevel: cefrLevel.lowercased(),
            domainTag: domainTag,
            partOfSpeech: partOfSpeech?.lowercased(),
            registerTag: registerTag?.lowercased(),
            frequencyBand: frequencyBand
        )
    }
}
