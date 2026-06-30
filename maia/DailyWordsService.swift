//
//  DailyWordsService.swift
//  maia
//
//  Günlük kelimeler artık tek kaynaktan: `maia/WordPacks/{yyyy-MM}.json`.
//  AI (Gemini) ve Firestore yazma yolu kapatıldı. Quiz soruları ve ekstra örnek
//  cümleler de aynı dosyalarda. Diary'deki correctSentence (tek AI özelliği)
//  hâlâ Functions üzerinden çalışır; bu servis ona dokunmuyor.
//

import Foundation

@MainActor
final class DailyWordsService {

    // MARK: - Manuel override (geliştirici)
    /// Geliştirme: belirli bir gün için seçimi WordPack'in dışına çıkarmak istersen.
    /// Yine WordPack'te tanımlı kelimelerden seçim yapar; o günü zorla bu 3 lemmayla doldurur.
    /// Örn: DailyWordsService.manualWordsByDate["2026-06-15"] = ["happy", "address", "anticipate"]
    static var manualWordsByDate: [String: [String]] = [:]

    // MARK: - Public API

    /// Belirli bir tarih için 3 kelime: WordPack'ten seç.
    /// Manuel override varsa onu uygular (hâlâ tanım/cümle/quiz WordPack'ten gelir).
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

    /// Today ekranı her yüklemede çağırır. WordPack'teki örnek cümleler zaten
    /// hedef kelimeyi içerecek şekilde elle yazıldığı için no-op; sadece geriye
    /// dönük uyum için ile imza korunur.
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

    // MARK: - Yardımcılar (eski API yüzeyini koruyan ufak hook'lar)

    /// QuizManager: aynı tarih/kelime için curated quizleri okur.
    static func curatedQuiz(forWord word: String, date: String) -> [WordPackQuiz]? {
        WordPackStore.shared.quizQuestions(forWord: word, date: date)
    }

    /// TodayTabView: Generate More akışında önceden yazılmış 2./3. cümleleri okur.
    static func extraExamples(forWord word: String, date: String) -> [String] {
        WordPackStore.shared.extraExampleSentences(forWord: word, date: date)
    }

    /// Eski WordOfTheDayManager hâlâ çağırıyor; CEFR uyumluluğu için aynı havuz bant kontrolü.
    static func poolHasBand(_ band: String) -> Bool {
        let lowered = band.lowercased()
        return [
            "a1", "a2", "b1", "b2", "c1", "c2"
        ].contains(lowered)
    }

    /// WordOfTheDayManager: yerel kilitli kelimeler hâlâ kullanılabilir mi (placeholder yok, örnek hedef kelimeyi içeriyor)?
    static func isUsableWordSet(_ words: [Word]) -> Bool {
        guard words.count == 3 else { return false }
        return !words.contains(where: hasPlaceholderContent)
            && words.allSatisfy(exampleIncludesHeadword)
    }

    /// WordOfTheDayManager.loadLockedWords çağırır; günlük kelimeler için hash uyumsuzluğu kontrolü.
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

    // MARK: - Hata mesajları

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

    // MARK: - Eski compat noktaları (artık no-op)

    /// Eski Firestore senkronizasyonu bu yeni mimaride yok; yine de çağrılırsa sorun olmasın.
    static func syncUsedWordsFromFirestoreOnce(userLevel _: Int) async {}
}
