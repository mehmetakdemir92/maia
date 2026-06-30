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
    /// Cloud TTS (Firebase Storage) kalıcı telaffuz URL’si; yoksa ilk dinlemede üretilir.
    let pronunciationAudioURL: String?
    /// 2. örnek cümle (WordOfTheDayManager'da aynı dosyada düzenlenebilir)
    let exampleSentence2: String?
    /// 3. örnek cümle (WordOfTheDayManager'da aynı dosyada düzenlenebilir)
    let exampleSentence3: String?

    // MARK: - Havuz etiketleri (DailyWordPool.txt; kişiselleştirilmiş öğrenme için)
    let cefrLevel: String?
    let domainTag: String?
    let partOfSpeech: String?
    let registerTag: String?
    let frequencyBand: Int?

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
        frequencyBand: Int? = nil
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
            frequencyBand: frequencyBand
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
            frequencyBand: frequencyBand
        )
    }
}

