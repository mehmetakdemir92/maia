//
//  PhoneticLookup.swift
//  maia
//
// Free dictionary API + local cache when WordPack has no phonetic.
//

import Foundation

enum PhoneticLookup {
    private static let cacheKey = "phoneticIPA.v1"

    private static var cache: [String: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: cacheKey),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    static func cachedIPA(for word: String) -> String? {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return cache[key]
    }

    static func ipa(for word: String) async -> String? {
        let key = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key], !cached.isEmpty { return cached }

        guard let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.dictionaryapi.dev/api/v2/entries/en/\(encoded)") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let first = json.first,
                  let phonetics = first["phonetics"] as? [[String: Any]] else {
                return nil
            }

            for item in phonetics {
                if let text = item["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        var dict = cache
                        dict[key] = trimmed
                        cache = dict
                        return trimmed
                    }
                }
            }
            return nil
        } catch {
            return nil
        }
    }
}
