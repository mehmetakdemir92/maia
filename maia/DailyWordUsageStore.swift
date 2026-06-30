//
//  DailyWordUsageStore.swift
//  maia
//
// Daily words tracked per level so C1/C2 pool is not polluted by A2 history.
//

import Foundation

@MainActor
final class DailyWordUsageStore {

    static let shared = DailyWordUsageStore()

    private static let legacyGlobalKey = "dailyWordTokensUsed"
    private static func levelKey(_ userLevel: Int) -> String {
        "dailyWordTokensUsed.l\(min(max(userLevel, 1), 11))"
    }

    private var cacheByLevel: [Int: Set<String>] = [:]

    private init() {
        migrateLegacyGlobalIfNeeded()
    }

    func usedLowercased(forLevel userLevel: Int) -> Set<String> {
        let level = min(max(userLevel, 1), 11)
        if let cached = cacheByLevel[level] { return cached }
        let key = Self.levelKey(level)
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            let set = Set(arr.map { $0.lowercased() })
            cacheByLevel[level] = set
            return set
        }
        return []
    }

    /// These words are excluded from daily selection at this level.
    func markUsed(words: [String], level userLevel: Int) {
        let level = min(max(userLevel, 1), 11)
        var set = usedLowercased(forLevel: level)
        var changed = false
        for w in words {
            if set.insert(w.lowercased()).inserted { changed = true }
        }
        if changed {
            cacheByLevel[level] = set
            save(set, level: level)
        }
    }

    /// Firestore sync: only words in the relevant level documents.
    func mergeUsedFromFirestore(words: [String], level userLevel: Int) {
        let level = min(max(userLevel, 1), 11)
        var set = usedLowercased(forLevel: level)
        var changed = false
        for w in words {
            if set.insert(w.lowercased()).inserted { changed = true }
        }
        if changed {
            cacheByLevel[level] = set
            save(set, level: level)
        }
    }

    func resetAll() {
        cacheByLevel = [:]
        UserDefaults.standard.removeObject(forKey: Self.legacyGlobalKey)
        for level in 1...11 {
            UserDefaults.standard.removeObject(forKey: Self.levelKey(level))
        }
    }

    private func save(_ set: Set<String>, level: Int) {
        let arr = Array(set)
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: Self.levelKey(level))
        }
    }

    /// One-time migration: copy legacy global list to all levels.
    private func migrateLegacyGlobalIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: Self.legacyGlobalKey),
              let arr = try? JSONDecoder().decode([String].self, from: data),
              !arr.isEmpty else { return }
        let legacy = Set(arr.map { $0.lowercased() })
        for level in 1...11 {
            var set = usedLowercased(forLevel: level)
            let before = set.count
            set.formUnion(legacy)
            if set.count != before {
                cacheByLevel[level] = set
                save(set, level: level)
            }
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyGlobalKey)
    }
}
