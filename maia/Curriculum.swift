//
//  Curriculum.swift
//  maia
//
// The linear word spine. Replaces the calendar-keyed WordPack: content is now a
// pure function of a slot index, not of a date, so every learner meets the same
// words at the same position in their own journey. Because a slot is
// deterministic, nothing needs to be "locked" for the day any more.
//

import Foundation

// MARK: - JSON models

/// Root of `maia/Curriculum/{en,de}.json` — one spine per learning language.
struct Curriculum: Codable, Equatable {
    let version: Int
    let language: String
    let slotCount: Int
    let slots: [CurriculumSlot]
}

/// One lesson unit: the fixed set of words met at this position in the spine.
struct CurriculumSlot: Codable, Equatable {
    /// 1-based position in the spine.
    let index: Int
    /// Short authoring label ("saying and implying"); optional UI heading.
    let theme: String?
    let words: [CurriculumWord]
}

struct CurriculumWord: Codable, Equatable {
    let word: String
    let cefrLevel: String
    let definition: String
    /// Three example sentences. Free users see the first; Generate More reveals the rest.
    let examples: [String]
    /// English glosses aligned 1:1 with `examples` (typically German spines).
    let exampleTranslations: [String]?
    /// Turkish glosses aligned 1:1 with `examples`.
    let exampleTranslationsTr: [String]?
    /// Authored quiz items. Item 0 is used on first exposure; later items are
    /// held back for spaced reviews so the learner is tested on the word rather
    /// than on a memorized question (see `QuizSessionBuilder`).
    let quiz: [CurriculumQuiz]
    let phonetic: String?
    let partOfSpeech: String?
    let domainTag: String?
    let registerTag: String?
    let frequencyBand: Int?

    init(
        word: String,
        cefrLevel: String,
        definition: String,
        examples: [String],
        quiz: [CurriculumQuiz],
        phonetic: String? = nil,
        partOfSpeech: String? = nil,
        domainTag: String? = nil,
        registerTag: String? = nil,
        frequencyBand: Int? = nil,
        exampleTranslations: [String]? = nil,
        exampleTranslationsTr: [String]? = nil
    ) {
        self.word = word
        self.cefrLevel = cefrLevel
        self.definition = definition
        self.examples = examples
        self.exampleTranslations = exampleTranslations
        self.exampleTranslationsTr = exampleTranslationsTr
        self.quiz = quiz
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.domainTag = domainTag
        self.registerTag = registerTag
        self.frequencyBand = frequencyBand
    }
}

/// Quiz item. `type` is informational; the renderer uses question/options as-is.
struct CurriculumQuiz: Codable, Equatable {
    let type: String
    let question: String
    let options: [String]
    let correctAnswerIndex: Int
}

// MARK: - Resource naming

extension LearningLanguage {
    /// Bundled spine resource name: `maia/Curriculum/{en,de}.json`.
    var curriculumResourceName: String { code }
}

// MARK: - Store

/// Reads the bundled spine and answers slot / lemma lookups.
@MainActor
final class CurriculumStore {
    static let shared = CurriculumStore()

    private var cache: [String: Curriculum] = [:]
    private var lemmaIndex: [String: [String: CurriculumWord]] = [:]
    private var missingLogged = Set<String>()

    private init() {}

    // MARK: Public API

    func curriculum(for language: LearningLanguage = .current) -> Curriculum? {
        let resource = language.curriculumResourceName
        if let cached = cache[resource] { return cached }
        guard let loaded = Self.load(resource: resource) else {
            if !missingLogged.contains(resource) {
                missingLogged.insert(resource)
                print("⚠️ Curriculum: \(resource).json bundle'da bulunamadı. " +
                      "`maia/Curriculum/\(resource).json` ekleyin (Xcode klasörü otomatik dahil eder).")
            }
            return nil
        }
        cache[resource] = loaded
        lemmaIndex[resource] = Dictionary(
            loaded.slots.flatMap(\.words).map { ($0.word.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return loaded
    }

    /// Number of authored slots. 0 means the spine is missing from the bundle.
    func slotCount(for language: LearningLanguage = .current) -> Int {
        curriculum(for: language)?.slots.count ?? 0
    }

    func slot(at index: Int, language: LearningLanguage = .current) -> CurriculumSlot? {
        guard let curriculum = curriculum(for: language) else { return nil }
        if let match = curriculum.slots.first(where: { $0.index == index }) { return match }
        // Tolerate a spine authored without explicit indices.
        guard index >= 1, index <= curriculum.slots.count else { return nil }
        return curriculum.slots[index - 1]
    }

    /// The words of one slot, ready for the UI.
    func words(atSlot index: Int, language: LearningLanguage = .current) -> [Word] {
        (slot(at: index, language: language)?.words ?? []).map { $0.toWord(language: language) }
    }

    /// Lemma lookup across the whole spine — used by reviews, which pull words
    /// the learner met many slots ago.
    func entry(forWord word: String, language: LearningLanguage = .current) -> CurriculumWord? {
        _ = curriculum(for: language)
        return lemmaIndex[language.curriculumResourceName]?[word.lowercased()]
    }

    func quizItems(forWord word: String, language: LearningLanguage = .current) -> [CurriculumQuiz]? {
        guard let entry = entry(forWord: word, language: language), !entry.quiz.isEmpty else { return nil }
        return entry.quiz
    }

    /// Generate More: the pre-written 2nd/3rd example sentences.
    func extraExampleSentences(forWord word: String, language: LearningLanguage = .current) -> [String] {
        guard let entry = entry(forWord: word, language: language), entry.examples.count > 1 else { return [] }
        return Array(entry.examples.dropFirst())
    }

    /// Authoring guard: a lemma must appear only once in the spine. `UUID.stable`
    /// is derived from the lemma, so a repeat would silently merge two slots'
    /// review histories into one word.
    func duplicateLemmas(for language: LearningLanguage = .current) -> [String] {
        guard let curriculum = curriculum(for: language) else { return [] }
        var seen = Set<String>()
        var duplicates: [String] = []
        for word in curriculum.slots.flatMap(\.words) {
            let key = word.word.lowercased()
            if !seen.insert(key).inserted, !duplicates.contains(key) {
                duplicates.append(key)
            }
        }
        return duplicates
    }

    // MARK: Internals

    private static func load(resource: String) -> Curriculum? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: resource, withExtension: "json", subdirectory: "Curriculum"),
            Bundle.main.url(forResource: resource, withExtension: "json")
        ]
        for case let url? in candidates {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                return try JSONDecoder().decode(Curriculum.self, from: data)
            } catch {
                print("⚠️ Curriculum: \(url.lastPathComponent) parse hatası:", error)
            }
        }
        return nil
    }
}

// MARK: - Word bridge

extension CurriculumWord {
    func toWord(language: LearningLanguage = .current) -> Word {
        let cleanedExamples = examples.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let primary = cleanedExamples.first ?? ""
        let second = cleanedExamples.indices.contains(1) ? cleanedExamples[1] : nil
        let third = cleanedExamples.indices.contains(2) ? cleanedExamples[2] : nil

        func cleaned(_ values: [String]?) -> [String] {
            (values ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        func gloss(_ values: [String], at index: Int) -> String? {
            guard values.indices.contains(index) else { return nil }
            let value = values[index]
            return value.isEmpty ? nil : value
        }

        let enGlosses = cleaned(exampleTranslations)
        let trGlosses = cleaned(exampleTranslationsTr)

        return Word(
            // Language in the id keeps en/de words with the same spelling distinct.
            // Derived from the lemma alone, so a word keeps its review history
            // even if the spine is reordered later.
            id: UUID.stable(from: language == .english
                ? word.lowercased()
                : "\(language.code)|\(word.lowercased())"),
            word: word,
            definition: definition,
            exampleSentence: primary,
            phonetic: phonetic,
            pronunciationAudioURL: nil,
            exampleSentence2: second,
            exampleSentence3: third,
            exampleTranslation: gloss(enGlosses, at: 0),
            exampleTranslation2: gloss(enGlosses, at: 1),
            exampleTranslation3: gloss(enGlosses, at: 2),
            exampleTranslationTr: gloss(trGlosses, at: 0),
            exampleTranslationTr2: gloss(trGlosses, at: 1),
            exampleTranslationTr3: gloss(trGlosses, at: 2),
            cefrLevel: cefrLevel.lowercased(),
            domainTag: domainTag,
            partOfSpeech: partOfSpeech?.lowercased(),
            registerTag: registerTag,
            frequencyBand: frequencyBand,
            languageCode: language.code
        )
    }
}
