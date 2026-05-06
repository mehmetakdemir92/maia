
//
//  WordPoolEntry.swift
//  maia
//
//  DailyWordPool.txt satırlarını parse eder. Kişiselleştirilmiş öğrenme için havuz etiketleri.
//

import Foundation

/// Havuzdaki tek kelime + isteğe bağlı etiketler.
struct WordPoolEntry: Equatable, Sendable {
    let word: String
    let cefrLevel: String?
    let domainTag: String?
    let partOfSpeech: String?
    /// Örn: neutral, formal, informal, spoken, written
    let registerTag: String?
    /// 1 = en yaygın çekirdek … 5 = nadir (özet bant; isteğe bağlı)
    let frequencyBand: Int?

    /// - Satırda `|` yoksa: tüm satır kelime (eski format).
    /// - `|` varsa: `kelime|cefr|domain|pos|register|frekans` — eksik sondaki alanlar boş olabilir.
    static func parseLine(_ line: String) -> WordPoolEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        guard trimmed.contains("|") else {
            return WordPoolEntry(
                word: trimmed,
                cefrLevel: nil,
                domainTag: nil,
                partOfSpeech: nil,
                registerTag: nil,
                frequencyBand: nil
            )
        }

        let parts = trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let rawWord = parts.first, !rawWord.isEmpty else { return nil }

        let cefr = parts.count > 1 ? nilIfEmpty(parts[1]) : nil
        let domain = parts.count > 2 ? nilIfEmpty(parts[2]) : nil
        let pos = parts.count > 3 ? nilIfEmpty(parts[3]) : nil
        let reg = parts.count > 4 ? nilIfEmpty(parts[4]) : nil
        let freq: Int? = parts.count > 5 ? Int(parts[5].trimmingCharacters(in: .whitespaces)) : nil

        return WordPoolEntry(
            word: rawWord,
            cefrLevel: cefr.map { $0.lowercased() },
            domainTag: domain,
            partOfSpeech: pos.map { $0.lowercased() },
            registerTag: reg.map { $0.lowercased() },
            frequencyBand: freq
        )
    }

    private static func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
