//
//  CEFRLevelMapping.swift
//  maia
//
//  Tek kaynak: ayarlar adımları (1–11) ↔ günlük kelime CEFR dağılımı.
//

import Foundation

enum CEFRLevelMapping {
    static let stepLabels: [String] = [
        "A1", "A1+", "A2", "A2+", "B1", "B1+", "B2", "B2+", "C1", "C1+", "C2"
    ]

    static func normalizedStep(_ userLevel: Int) -> Int {
        min(max(userLevel, 1), stepLabels.count)
    }

    static func label(for userLevel: Int) -> String {
        let step = normalizedStep(userLevel)
        return stepLabels[step - 1]
    }

    /// Örn. B2+ (8) → ["c1", "c1", "b2"]
    static func preferredBands(for userLevel: Int) -> [String] {
        switch normalizedStep(userLevel) {
        case 1: return ["a1", "a1", "a2"]
        case 2: return ["a2", "a2", "a1"]
        case 3: return ["a2", "a2", "b1"]
        case 4: return ["b1", "b1", "a2"]
        case 5: return ["b1", "b1", "b2"]
        case 6: return ["b1", "b1", "b2"]
        case 7: return ["b2", "b2", "c1"]
        case 8: return ["c1", "c1", "b2"] // B2+
        case 9: return ["c1", "c1", "c2"]
        case 10: return ["c1", "c1", "c2"]
        case 11: return ["c2", "c2", "c1"]
        default: return ["a1", "a1", "a2"]
        }
    }

    /// Kullanıcıya gösterilecek hedef dağılım: "2× C1, 1× B2"
    static func preferredBandsSummary(for userLevel: Int) -> String {
        let bands = preferredBands(for: userLevel)
        let counts = Dictionary(grouping: bands, by: { $0.uppercased() })
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
        return counts.map { "\($0.value)× \($0.key)" }.joined(separator: ", ")
    }

    /// Havuzda hedef bant yoksa bir alt/üst banta düş — B2+ için B1'e inme.
    static func substituteBands(for band: String, userLevel: Int) -> [String] {
        let level = normalizedStep(userLevel)
        switch (level, band) {
        case (8...11, "c2"): return ["c1", "b2"]
        case (8...11, "c1"): return ["c2", "b2"]
        case (7...11, "b2"): return ["c1", "c2"]
        case (5...7, "b2"): return ["c1", "b1"]
        case (5...6, "b1"): return ["b2", "a2"]
        case (3...4, "b1"): return ["b2", "a2"]
        case (2...3, "a2"): return ["b1", "a1"]
        case (1...2, "a1"): return ["a2"]
        default: return []
        }
    }

    /// Kalan slotları doldururken öncelik (yüksek seviye: C2/C1/B2).
    static func fallbackBandPriority(for userLevel: Int) -> [String] {
        switch normalizedStep(userLevel) {
        case 11, 10, 9, 8: return ["c2", "c1", "b2", "b1"]
        case 7: return ["c1", "b2", "b1", "a2"]
        case 6, 5: return ["b2", "b1", "a2", "c1"]
        case 4, 3: return ["b1", "a2", "b2", "a1"]
        case 2: return ["a2", "a1", "b1"]
        default: return ["a1", "a2", "b1"]
        }
    }

    static func matchesPreferredBands(_ words: [Word], userLevel: Int) -> Bool {
        let expected = preferredBands(for: userLevel).map { $0.lowercased() }.sorted()
        let actual = cefrBands(from: words).sorted()
        return actual.count == 3 && actual == expected
    }

    /// Tam eşleşme her zaman kabul; aksi halde yalnız hedef bantlar bu cihazın havuzunda yoksa yedek dağılım kabul.
    /// Bu sayede havuz hedef bantları üretebildiği halde Firestore'da yanlış dağılım kalmışsa yenilenmeye zorlanır.
    static func isAcceptableCEFRDistribution(
        _ words: [Word],
        userLevel: Int,
        poolHasBand: (String) -> Bool = { _ in true }
    ) -> Bool {
        guard words.count == 3 else { return false }
        if matchesPreferredBands(words, userLevel: userLevel) { return true }

        let preferred = preferredBands(for: userLevel).map { $0.lowercased() }
        let canSatisfyPreferred = preferred.allSatisfy(poolHasBand)
        if canSatisfyPreferred { return false }

        let level = normalizedStep(userLevel)
        guard level >= 8 else { return false }
        let bands = cefrBands(from: words)
        guard bands.count == 3 else { return false }
        let allowed = Set(fallbackBandPriority(for: userLevel))
        return bands.allSatisfy { allowed.contains($0) }
    }

    private static func cefrBands(from words: [Word]) -> [String] {
        words.map { ($0.cefrLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}
