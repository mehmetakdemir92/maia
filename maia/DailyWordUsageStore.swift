//
//  DailyWordUsageStore.swift
//  maia
//
//  Bir gün gösterilen günlük kelimeler burada kalıcı tutulur; bir daha seçilmez.
//

import Foundation

@MainActor
final class DailyWordUsageStore {

    static let shared = DailyWordUsageStore()

    private let key = "dailyWordTokensUsed"

    private(set) var usedLowercased: Set<String> = []

    private init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            usedLowercased = Set(arr.map { $0.lowercased() })
        }
    }

    /// Bu kelimeler artık günlük seçimde kullanılmaz (küçük harf normalize).
    func markUsed(words: [String]) {
        var changed = false
        for w in words {
            if usedLowercased.insert(w.lowercased()).inserted {
                changed = true
            }
        }
        if changed { save() }
    }

    /// Firestore senkronundan sonra: tüm günlük kelimelerin birebir kümesi (tekrar yok kuralı için kaynak).
    func replaceAll(with lemmas: Set<String>) {
        usedLowercased = lemmas
        save()
    }

    /// Clears persisted daily-word exclusion state (used to be global; reset on account switch).
    func resetAll() {
        usedLowercased = []
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save() {
        let arr = Array(usedLowercased)
        if let data = try? JSONEncoder().encode(arr) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
