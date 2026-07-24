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

    // MARK: - Pool tags (DailyWordPool.txt)
    let cefrLevel: String?
    let domainTag: String?
    let partOfSpeech: String?
    let registerTag: String?
    let frequencyBand: Int?
    /// Pre-written quiz from WordPack JSON; attached when the word is loaded.
    let packQuizzes: [WordPackQuiz]?
    /// Calendar day (yyyy-MM-dd) this word was loaded from in WordPack.
    let packDayISO: String?

    init(
        id: UUID = UUID(),
        word: String,
        definition: String,
        exampleSentence: String,
        phonetic: String? = nil,
        pronunciationAudioURL: String? = nil,
        exampleSentence2: String? = nil,
        exampleSentence3: String? = nil,
        cefrLevel: String? = nil,
        domainTag: String? = nil,
        partOfSpeech: String? = nil,
        registerTag: String? = nil,
        frequencyBand: Int? = nil,
        packQuizzes: [WordPackQuiz]? = nil,
        packDayISO: String? = nil
    ) {
        self.id = id
        self.word = word
        self.definition = definition
        self.exampleSentence = exampleSentence
        self.phonetic = phonetic
        self.pronunciationAudioURL = pronunciationAudioURL
        self.exampleSentence2 = exampleSentence2
        self.exampleSentence3 = exampleSentence3
        self.cefrLevel = cefrLevel
        self.domainTag = domainTag
        self.partOfSpeech = partOfSpeech
        self.registerTag = registerTag
        self.frequencyBand = frequencyBand
        self.packQuizzes = packQuizzes
        self.packDayISO = packDayISO
    }

    private enum CodingKeys: String, CodingKey {
        case id, word, definition, exampleSentence, phonetic, pronunciationAudioURL
        case exampleSentence2, exampleSentence3
        case cefrLevel, domainTag, partOfSpeech, registerTag, frequencyBand
        case packDayISO
        // packQuizzes intentionally omitted — always loaded fresh from WordPack JSON in the bundle.
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        word = try c.decode(String.self, forKey: .word)
        definition = try c.decode(String.self, forKey: .definition)
        exampleSentence = try c.decode(String.self, forKey: .exampleSentence)
        phonetic = try c.decodeIfPresent(String.self, forKey: .phonetic)
        pronunciationAudioURL = try c.decodeIfPresent(String.self, forKey: .pronunciationAudioURL)
        exampleSentence2 = try c.decodeIfPresent(String.self, forKey: .exampleSentence2)
        exampleSentence3 = try c.decodeIfPresent(String.self, forKey: .exampleSentence3)
        cefrLevel = try c.decodeIfPresent(String.self, forKey: .cefrLevel)
        domainTag = try c.decodeIfPresent(String.self, forKey: .domainTag)
        partOfSpeech = try c.decodeIfPresent(String.self, forKey: .partOfSpeech)
        registerTag = try c.decodeIfPresent(String.self, forKey: .registerTag)
        frequencyBand = try c.decodeIfPresent(Int.self, forKey: .frequencyBand)
        packDayISO = try c.decodeIfPresent(String.self, forKey: .packDayISO)
        packQuizzes = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(word, forKey: .word)
        try c.encode(definition, forKey: .definition)
        try c.encode(exampleSentence, forKey: .exampleSentence)
        try c.encodeIfPresent(phonetic, forKey: .phonetic)
        try c.encodeIfPresent(pronunciationAudioURL, forKey: .pronunciationAudioURL)
        try c.encodeIfPresent(exampleSentence2, forKey: .exampleSentence2)
        try c.encodeIfPresent(exampleSentence3, forKey: .exampleSentence3)
        try c.encodeIfPresent(cefrLevel, forKey: .cefrLevel)
        try c.encodeIfPresent(domainTag, forKey: .domainTag)
        try c.encodeIfPresent(partOfSpeech, forKey: .partOfSpeech)
        try c.encodeIfPresent(registerTag, forKey: .registerTag)
        try c.encodeIfPresent(frequencyBand, forKey: .frequencyBand)
        try c.encodeIfPresent(packDayISO, forKey: .packDayISO)
    }

    /// Attaches the latest quiz questions from the bundled WordPack (never from UserDefaults cache).
    @MainActor
    func withHydratedQuizzes(dayISO: String) -> Word {
        let quizzes = WordPackStore.shared.quizQuestions(forWord: word, date: dayISO)
        return Word(
            id: id,
            word: word,
            definition: definition,
            exampleSentence: exampleSentence,
            phonetic: phonetic,
            pronunciationAudioURL: pronunciationAudioURL,
            exampleSentence2: exampleSentence2,
            exampleSentence3: exampleSentence3,
            cefrLevel: cefrLevel,
            domainTag: domainTag,
            partOfSpeech: partOfSpeech,
            registerTag: registerTag,
            frequencyBand: frequencyBand,
            packQuizzes: quizzes,
            packDayISO: dayISO
        )
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
            cefrLevel: cefrLevel,
            domainTag: domainTag,
            partOfSpeech: partOfSpeech,
            registerTag: registerTag,
            frequencyBand: frequencyBand,
            packQuizzes: packQuizzes,
            packDayISO: packDayISO
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
            cefrLevel: cefrLevel,
            domainTag: domainTag,
            partOfSpeech: partOfSpeech,
            registerTag: registerTag,
            frequencyBand: frequencyBand,
            packQuizzes: packQuizzes,
            packDayISO: packDayISO
        )
    }
}

