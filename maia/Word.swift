//
//  Word.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import Foundation
import CryptoKit

extension UUID {
    static func stable(from string: String) -> UUID {
        let hash = SHA256.hash(data: Data(string.utf8))
        let bytes = Array(hash.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            (bytes[6] & 0x0F) | 0x40, bytes[7], // Version 4
            (bytes[8] & 0x3F) | 0x80, bytes[9], // Variant
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

struct Word: Identifiable, Codable, Equatable {
    let id: UUID
    let word: String
    let definition: String
    let exampleSentence: String
    let phonetic: String?
    /// Persistent cloud TTS URL; generated on first play if missing.
    let pronunciationAudioURL: String?
    /// Second example sentence
    let exampleSentence2: String?
    /// Third example sentence
    let exampleSentence3: String?
    /// English gloss for `exampleSentence` (typically German learning packs).
    let exampleTranslation: String?
    let exampleTranslation2: String?
    let exampleTranslation3: String?
    /// Turkish glosses aligned with the example sentences.
    let exampleTranslationTr: String?
    let exampleTranslationTr2: String?
    let exampleTranslationTr3: String?

    // MARK: - Pool tags (DailyWordPool.txt)
    let cefrLevel: String?
    let domainTag: String?
    let partOfSpeech: String?
    let registerTag: String?
    let frequencyBand: Int?

    /// ISO 639-1 learning-language code ("en", "de"). nil = legacy English data.
    let languageCode: String?

    var learningLanguage: LearningLanguage {
        LearningLanguage.fromCode(languageCode)
    }

    init(
        id: UUID = UUID(),
        word: String,
        definition: String,
        exampleSentence: String,
        phonetic: String? = nil,
        pronunciationAudioURL: String? = nil,
        exampleSentence2: String? = nil,
        exampleSentence3: String? = nil,
        exampleTranslation: String? = nil,
        exampleTranslation2: String? = nil,
        exampleTranslation3: String? = nil,
        exampleTranslationTr: String? = nil,
        exampleTranslationTr2: String? = nil,
        exampleTranslationTr3: String? = nil,
        cefrLevel: String? = nil,
        domainTag: String? = nil,
        partOfSpeech: String? = nil,
        registerTag: String? = nil,
        frequencyBand: Int? = nil,
        languageCode: String? = nil
    ) {
        self.id = id
        self.word = word
        self.definition = definition
        self.exampleSentence = exampleSentence
        self.phonetic = phonetic
        self.pronunciationAudioURL = pronunciationAudioURL
        self.exampleSentence2 = exampleSentence2
        self.exampleSentence3 = exampleSentence3
        self.exampleTranslation = exampleTranslation
        self.exampleTranslation2 = exampleTranslation2
        self.exampleTranslation3 = exampleTranslation3
        self.exampleTranslationTr = exampleTranslationTr
        self.exampleTranslationTr2 = exampleTranslationTr2
        self.exampleTranslationTr3 = exampleTranslationTr3
        self.cefrLevel = cefrLevel
        self.domainTag = domainTag
        self.partOfSpeech = partOfSpeech
        self.registerTag = registerTag
        self.frequencyBand = frequencyBand
        self.languageCode = languageCode
    }

    /// Gloss under an example sentence.
    /// - Prefer `preferredLanguageCode` (`tr` / `en`) when it differs from the learning language.
    /// - Learning DE: fall back to English if preferred gloss is missing.
    /// - Learning EN: only Turkish (or preferred non-English) glosses; no English-under-English.
    func gloss(forExample sentence: String, preferredLanguageCode: String?) -> String? {
        let key = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        guard let preferred = preferredLanguageCode?.lowercased(), !preferred.isEmpty else {
            return nil
        }

        let learning = learningLanguage.code

        // Same language as the example → no gloss.
        if preferred == learning {
            return nil
        }

        if preferred == "tr", let tr = translation(for: key, language: "tr") {
            return tr
        }
        if preferred == "en", let en = translation(for: key, language: "en") {
            return en
        }

        // Fallbacks when preferred gloss is missing from the pack.
        if learning == "de" {
            return translation(for: key, language: "en")
        }
        if learning == "en" {
            return translation(for: key, language: "tr")
        }
        return nil
    }

    /// Legacy helper used by older call sites.
    func englishGloss(forExample sentence: String) -> String? {
        gloss(forExample: sentence, preferredLanguageCode: "en")
    }

    private func translation(for sentence: String, language: String) -> String? {
        let pairs: [(String?, String?)]
        switch language {
        case "tr":
            pairs = [
                (exampleSentence, exampleTranslationTr),
                (exampleSentence2, exampleTranslationTr2),
                (exampleSentence3, exampleTranslationTr3),
            ]
        default:
            pairs = [
                (exampleSentence, exampleTranslation),
                (exampleSentence2, exampleTranslation2),
                (exampleSentence3, exampleTranslation3),
            ]
        }
        for (example, translation) in pairs {
            guard
                let example,
                let translation,
                example.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(sentence) == .orderedSame
            else { continue }
            let gloss = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            return gloss.isEmpty ? nil : gloss
        }
        return nil
    }

    func withExampleSentence(_ sentence: String) -> Word {
        Word(
            id: id,
            word: word,
            definition: definition,
            exampleSentence: sentence,
            phonetic: phonetic,
            pronunciationAudioURL: pronunciationAudioURL,
            exampleSentence2: exampleSentence2,
            exampleSentence3: exampleSentence3,
            exampleTranslation: nil,
            exampleTranslation2: exampleTranslation2,
            exampleTranslation3: exampleTranslation3,
            exampleTranslationTr: nil,
            exampleTranslationTr2: exampleTranslationTr2,
            exampleTranslationTr3: exampleTranslationTr3,
            cefrLevel: cefrLevel,
            domainTag: domainTag,
            partOfSpeech: partOfSpeech,
            registerTag: registerTag,
            frequencyBand: frequencyBand,
            languageCode: languageCode
        )
    }

    func withPronunciationAudioURL(_ url: String?) -> Word {
        Word(
            id: id,
            word: word,
            definition: definition,
            exampleSentence: exampleSentence,
            phonetic: phonetic,
            pronunciationAudioURL: url,
            exampleSentence2: exampleSentence2,
            exampleSentence3: exampleSentence3,
            exampleTranslation: exampleTranslation,
            exampleTranslation2: exampleTranslation2,
            exampleTranslation3: exampleTranslation3,
            exampleTranslationTr: exampleTranslationTr,
            exampleTranslationTr2: exampleTranslationTr2,
            exampleTranslationTr3: exampleTranslationTr3,
            cefrLevel: cefrLevel,
            domainTag: domainTag,
            partOfSpeech: partOfSpeech,
            registerTag: registerTag,
            frequencyBand: frequencyBand,
            languageCode: languageCode
        )
    }
}
