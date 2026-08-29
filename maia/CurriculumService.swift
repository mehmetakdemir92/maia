//
//  CurriculumService.swift
//  maia
//
// Resolves the words of a slot and attaches pronunciation audio.
// Replaces DailyWordsService: no date keys, no per-level selection, no
// used-word bookkeeping — a slot is the same five words for everyone.
//

import Foundation

@MainActor
final class CurriculumService {

    enum ServiceError: LocalizedError {
        case missingSpine(LearningLanguage)
        case slotOutOfRange(index: Int, slotCount: Int)

        var errorDescription: String? {
            switch self {
            case .missingSpine(let language):
                return String(
                    format: String(localized: "The word list is missing. Add maia/Curriculum/%@.json and rebuild."),
                    language.curriculumResourceName
                )
            case .slotOutOfRange:
                return String(localized: "You've finished every lesson we've written so far. New words are on the way.")
            }
        }
    }

    /// The words of one slot, with audio resolved.
    func words(forSlot index: Int, language: LearningLanguage = .current) async throws -> [Word] {
        let slotCount = CurriculumStore.shared.slotCount(for: language)
        guard slotCount > 0 else { throw ServiceError.missingSpine(language) }
        guard index >= 1, index <= slotCount else {
            throw ServiceError.slotOutOfRange(index: index, slotCount: slotCount)
        }

        let words = CurriculumStore.shared.words(atSlot: index, language: language)
        guard !words.isEmpty else {
            throw ServiceError.slotOutOfRange(index: index, slotCount: slotCount)
        }
        return await Self.attachPronunciations(to: words)
    }

    /// Look a word up anywhere in the spine — reviews reach far back.
    static func word(forLemma lemma: String, language: LearningLanguage = .current) -> Word? {
        CurriculumStore.shared.entry(forWord: lemma, language: language)?.toWord(language: language)
    }

    /// TodayTabView: pre-written 2nd/3rd sentences for Generate More.
    static func extraExamples(forWord word: String, language: LearningLanguage = .current) -> [String] {
        CurriculumStore.shared.extraExampleSentences(forWord: word, language: language)
    }

    /// QuizManager: authored quiz items for a word.
    static func curatedQuiz(forWord word: String, language: LearningLanguage = .current) -> [CurriculumQuiz]? {
        CurriculumStore.shared.quizItems(forWord: word, language: language)
    }

    /// Authoring guard: every example must actually contain its headword.
    static func exampleIncludesHeadword(_ word: Word) -> Bool {
        let lemma = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lemma.isEmpty else { return true }
        let example = word.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !example.isEmpty else { return false }

        let escaped = NSRegularExpression.escapedPattern(for: lemma)
        let options: NSString.CompareOptions = [.regularExpression, .caseInsensitive]
        if example.range(of: "\\b\(escaped)\\b", options: options) != nil { return true }

        for suffix in word.learningLanguage.headwordSuffixes {
            if example.range(of: "\\b\(escaped)\(suffix)\\b", options: options) != nil { return true }
        }
        return false
    }

    // MARK: - Pronunciation

    private static func attachPronunciations(to words: [Word]) async -> [Word] {
        var updated = words
        await withTaskGroup(of: (Int, String?).self) { group in
            for (index, item) in words.enumerated() where item.pronunciationAudioURL == nil {
                group.addTask {
                    let url = await WordPronunciationService.shared.resolveAudioURL(
                        for: item.word,
                        language: item.learningLanguage
                    )
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
}
