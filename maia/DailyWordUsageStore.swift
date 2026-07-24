//
//  DailyWordUsageStore.swift
//  maia
//
// Daily words tracked per level so C1/C2 pool is not polluted by A2 history.
// Keys are additionally namespaced per learning language (English keeps the
// legacy keys so existing user data stays valid).
//

import Foundation

@MainActor
final class DailyWordUsageStore {

    static let shared = DailyWordUsageStore()

    private static let legacyGlobalKey = "dailyWordTokensUsed"
    private static func levelKey(_ userLevel: Int, language: LearningLanguage) -> String {
        "dailyWordTokensUsed\(language.storageSuffix).l\(min(max(userLevel, 1), 11))"
    }

    private var cacheByKey: [String: Set<String>] = [:]

    private init() {
        migrateLegacyGlobalIfNeeded()
    }

    func usedLowercased(forLevel userLevel: Int, language: LearningLanguage = .current) -> Set<String> {
        let key = Self.levelKey(userLevel, language: language)
        if let cached = cacheByKey[key] { return cached }
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            let set = Set(arr.map { $0.lowercased() })
            cacheByKey[key] = set
            return set
        }
        return []
    }

    /// These words are excluded from daily selection at this level.
    func markUsed(words: [String], level userLevel: Int, language: LearningLanguage = .current) {
        insert(words: words, level: userLevel, language: language)
    }

    /// Firestore sync: only words in the relevant level documents.
    func mergeUsedFromFirestore(words: [String], level userLevel: Int, language: LearningLanguage = .current) {
        insert(words: words, level: userLevel, language: language)
    }

    func resetAll() {
        cacheByKey = [:]
        UserDefaults.standard.removeObject(forKey: Self.legacyGlobalKey)
        for language in LearningLanguage.allCases {
            for level in 1...11 {
                UserDefaults.standard.removeObject(forKey: Self.levelKey(level, language: language))
            }
        }
    }

    private func insert(words: [String], level userLevel: Int, language: LearningLanguage) {
        let key = Self.levelKey(userLevel, language: language)
        var set = usedLowercased(forLevel: userLevel, language: language)
        var changed = false
        for w in words {
            if set.insert(w.lowercased()).inserted { changed = true }
        }
        if changed {
            cacheByKey[key] = set
            save(set, key: key)
        }
    }

    private func save(_ set: Set<String>, key: String) {
        let arr = Array(set)
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// One-time migration: copy legacy global list to all English levels.
    private func migrateLegacyGlobalIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyGlobalKey),
              let arr = try? JSONDecoder().decode([String].self, from: data),
              !arr.isEmpty else { return }
        let legacy = Set(arr.map { $0.lowercased() })
        for level in 1...11 {
            var set = usedLowercased(forLevel: level, language: .english)
            let before = set.count
            set.formUnion(legacy)
            if set.count != before {
                let key = Self.levelKey(level, language: .english)
                cacheByKey[key] = set
                save(set, key: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyGlobalKey)
    }
}
