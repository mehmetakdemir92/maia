//
//  DailyWordsService.swift
//  maia
//
//  Created by Mehmet Akdemir on 9.02.2026.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

@MainActor
final class DailyWordsService {

    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    private let baseURL = URL(string: "https://gemini-backend-359781552395.europe-west4.run.app")!

    private let collectionName = "dailyWords"
    
    private static func normalizedLevel(_ userLevel: Int) -> Int {
        min(max(userLevel, 1), 11)
    }
    
    private static func dailyWordsDocumentID(date: String, userLevel: Int) -> String {
        "\(date)_l\(normalizedLevel(userLevel))"
    }
    
    private static func hasPlaceholderContent(_ word: Word) -> Bool {
        let definition = word.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        let example = word.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWord = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholderDefinition = "A useful English word to practice today."
        let placeholderExample = "I use \(normalizedWord) in my English practice today."
        return definition == placeholderDefinition || example == placeholderExample
    }
    
    private static func isUsableWordSet(_ words: [Word]) -> Bool {
        guard words.count == 3 else { return false }
        return !words.contains(where: hasPlaceholderContent)
    }

    /// Havuz: `DailyWordPool.txt` — kelime veya `kelime|cefr|domain|pos|register|frekans` (bkz. dosya başlığı).
    private static let curatedPoolEntries: [WordPoolEntry] = {
        let loaded = loadWordPoolEntriesFromBundle()
        let deduped = dedupeEntriesPreservingOrder(loaded)
        if !deduped.isEmpty { return deduped }
        assertionFailure("DailyWordPool.txt bulunamadı veya boş; Target’a eklendiğinden emin ol.")
        return ["learn", "practice", "review", "study", "focus", "habit"].map {
            WordPoolEntry.parseLine($0)! // düz kelime satırı
        }
    }()

    private static let poolEntryByLemma: [String: WordPoolEntry] = {
        Dictionary(uniqueKeysWithValues: curatedPoolEntries.map { ($0.word.lowercased(), $0) })
    }()

    private static func loadWordPoolEntriesFromBundle() -> [WordPoolEntry] {
        guard let url = Bundle.main.url(forResource: "DailyWordPool", withExtension: "txt"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return raw
            .split(whereSeparator: \.isNewline)
            .compactMap { WordPoolEntry.parseLine(String($0)) }
    }

    private static func dedupeEntriesPreservingOrder(_ entries: [WordPoolEntry]) -> [WordPoolEntry] {
        var seen = Set<String>()
        var out: [WordPoolEntry] = []
        for e in entries {
            let k = e.word.lowercased()
            if !seen.contains(k) {
                seen.insert(k)
                out.append(e)
            }
        }
        return out
    }

    private static func poolEntry(forLemma lemma: String) -> WordPoolEntry? {
        poolEntryByLemma[lemma.lowercased()]
    }

    private static func dedupePoolPreservingOrder(_ words: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for w in words {
            let k = w.lowercased()
            if !seen.contains(k) {
                seen.insert(k)
                out.append(w)
            }
        }
        return out
    }

    /// FNV-1a 64-bit: süreçler/cihazlar arası stabil hash.
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603 // FNV-1a offset
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    /// Gün + kelimeye göre deterministik puan. Alfabetik ardışıklığı kırmak için kullanılır.
    private static func stableWordScore(date: String, word: String) -> UInt64 {
        stableHash("\(date)|\(word.lowercased())")
    }

    /// Daha önce hiçbir günde kullanılmamış kelimelerden, tarihe ve kullanıcı seviyesine göre deterministik 3 kelime.
    /// Havuzda 3'ten az kullanılmamış kelime kaldıysa tekrar yapılmaz; boş liste döner.
    private static func wordsForDate(_ date: String, userLevel: Int) -> [String] {
        wordsForDate(date, usedSnapshot: DailyWordUsageStore.shared.usedLowercased, userLevel: userLevel)
    }

    /// `usedSnapshot`: karşılaştırma için bugünün Firestore kelimeleri geçici olarak dışarıda bırakılabilir (`subtracting`).
    private static func wordsForDate(_ date: String, usedSnapshot: Set<String>, userLevel: Int) -> [String] {
        let pool = dedupeEntriesPreservingOrder(curatedPoolEntries)
        guard !pool.isEmpty else {
            return ["learn", "practice", "review"]
        }
        let available = pool.filter { !usedSnapshot.contains($0.word.lowercased()) }

        guard available.count >= 3 else {
            print("⚠️ DailyWords: Kullanılmamış kelime \(available.count) adet (<3). Tekrar yapılmıyor.")
            return []
        }

        func rankedWords(_ entries: [WordPoolEntry], salt: String) -> [WordPoolEntry] {
            entries.sorted { lhs, rhs in
                let lScore = stableWordScore(date: "\(date)|\(salt)", word: lhs.word)
                let rScore = stableWordScore(date: "\(date)|\(salt)", word: rhs.word)
                if lScore != rScore { return lScore < rScore }
                return lhs.word.lowercased() < rhs.word.lowercased()
            }
        }

        let desiredBands = preferredCEFRBands(for: userLevel)
        var selected: [WordPoolEntry] = []
        var selectedWords = Set<String>()
        var remaining = available

        for band in desiredBands {
            let bucket = remaining.filter { ($0.cefrLevel ?? "").lowercased() == band }
            guard let pick = rankedWords(bucket, salt: "band-\(band)").first else { continue }
            selected.append(pick)
            selectedWords.insert(pick.word.lowercased())
            remaining.removeAll { $0.word.lowercased() == pick.word.lowercased() }
        }

        if selected.count < 3 {
            let leftovers = remaining.filter { !selectedWords.contains($0.word.lowercased()) }
            for entry in rankedWords(leftovers, salt: "fallback") {
                guard selected.count < 3 else { break }
                selected.append(entry)
                selectedWords.insert(entry.word.lowercased())
            }
        }

        guard selected.count == 3 else {
            print("⚠️ DailyWords: Seviye dağıtımı için yeterli kelime bulunamadı.")
            return []
        }

        let finalRanked = selected.sorted { lhs, rhs in
            let lScore = stableWordScore(date: date, word: lhs.word)
            let rScore = stableWordScore(date: date, word: rhs.word)
            if lScore != rScore { return lScore < rScore }
            return lhs.word.lowercased() < rhs.word.lowercased()
        }
        return finalRanked.map(\.word)
    }

    private static func preferredCEFRBands(for userLevel: Int) -> [String] {
        switch min(max(userLevel, 1), 11) {
        case 1: return ["a1", "a1", "a2"] // A1 -> 2x A1, 1x A2
        case 2: return ["a2", "a2", "a1"] // A1+ -> 2x A2, 1x A1
        case 3: return ["a2", "a2", "b1"] // A2 -> 2x A2, 1x B1
        case 4: return ["b1", "b1", "a2"] // A2+ -> 2x B1, 1x A2
        case 5: return ["b1", "b1", "b2"] // B1 -> 2x B1, 1x B2
        case 6: return ["b1", "b1", "b2"] // B1+ -> 2x B1, 1x B2
        case 7: return ["b2", "b2", "c1"] // B2 -> 2x B2, 1x C1
        case 8: return ["c1", "c1", "b2"] // B2+ -> 2x C1, 1x B2
        case 9: return ["c1", "c1", "c2"] // C1 -> 2x C1, 1x C2
        case 10: return ["c1", "c1", "c2"] // C1+ -> 2x C1, 1x C2
        case 11: return ["c2", "c2", "c1"] // C2 -> 2x C2, 1x C1
        default: return ["a1", "a1", "a2"]
        }
    }

    /// Firestore’daki üçlü, “bugünün kelimeleri `used` dışında sayıldığında” algoritmanın üreteceği üçlüyle aynı değilse önbellek bayat.
    static func isFirestoreCacheStale(parsed: [Word], date: String, userLevel: Int) -> Bool {
        _ = date
        _ = userLevel
        return !isUsableWordSet(parsed)
    }

    /// Firestore’daki tüm günlük kelime dokümanlarındaki kelimeleri yerel “kullanıldı” listesine alır (bir kez, uygulama ömrü boyunca).
    static func syncUsedWordsFromFirestoreOnce() async {
        guard !didSyncUsedFromFirestore else { return }
        didSyncUsedFromFirestore = true
        let snap: QuerySnapshot
        do {
            snap = try await Firestore.firestore().collection("dailyWords").getDocuments()
        } catch {
            didSyncUsedFromFirestore = false
            print("⚠️ syncUsedWordsFromFirestore:", error)
            return
        }
        for doc in snap.documents {
            guard let arr = doc.data()["words"] as? [[String: Any]] else { continue }
            let ws = arr.compactMap { $0["word"] as? String }
            DailyWordUsageStore.shared.markUsed(words: ws)
        }
    }

    private static var didSyncUsedFromFirestore = false
    private static var fallbackWordsByDate: [String: [Word]] = [:]

    private static func fallbackCacheKey(date: String, userLevel: Int) -> String {
        "\(date)|l\(normalizedLevel(userLevel))"
    }

    /// Manuel seçim: istediğin tarih için 3 kelime atayabilirsin. Key: "yyyy-MM-dd", value: tam 3 kelime.
    /// Örnek: DailyWordsService.manualWordsByDate["2026-03-03"] = ["anticipate", "benefit", "challenge"]
    static var manualWordsByDate: [String: [String]] = [:]

    /// Bir tarih için kullanılacak 3 kelime: önce manualWordsByDate’e bak, yoksa hash ile seç.
    private static func wordsForDateOrManual(_ date: String, userLevel: Int) -> [String] {
        if let manual = manualWordsByDate[date], manual.count == 3 { return manual }
        return wordsForDate(date, userLevel: userLevel)
    }

    /// Hangi tarihte hangi 3 kelimenin geleceğini önizlemek için. Tarih formatı: "yyyy-MM-dd".
    static func previewWords(for dateString: String, userLevel: Int = 1) -> [String] {
        wordsForDateOrManual(dateString, userLevel: userLevel)
    }

    func ensureDailyWords(date: String, category: String, userLevel: Int) async throws -> [Word] {
        await Self.syncUsedWordsFromFirestoreOnce()

        let hasManual = Self.manualWordsByDate[date]?.count == 3
        if hasManual {
            return try await buildWordsFromEnrichOnly(date: date, category: category, userLevel: userLevel)
        }

        let docID = Self.dailyWordsDocumentID(date: date, userLevel: userLevel)
        let ref = db.collection(collectionName).document(docID)
        let existing = try await ref.getDocument()
        if let data = existing.data(),
           let arr = data["words"] as? [[String: Any]] {
            let parsed = Self.parseWordsFromFirestore(arr)
            if Self.isUsableWordSet(parsed) {
                DailyWordUsageStore.shared.markUsed(words: parsed.map(\.word))
                return parsed
            }
        }
        
        if Self.normalizedLevel(userLevel) == 1 {
            let legacyRef = db.collection(collectionName).document(date)
            let legacyExisting = try await legacyRef.getDocument()
            if let legacyData = legacyExisting.data(),
               let arr = legacyData["words"] as? [[String: Any]] {
                let parsed = Self.parseWordsFromFirestore(arr)
                if Self.isUsableWordSet(parsed) {
                    DailyWordUsageStore.shared.markUsed(words: parsed.map(\.word))
                    return parsed
                }
            }
        }

        return try await ensureDailyWordsFromServer(date: date, category: category, userLevel: userLevel)
    }

    /// Firestore `dailyWords` artık yalnızca Cloud Function (Admin) tarafından yazılır; istemci callable çağırır.
    private func ensureDailyWordsFromServer(date: String, category: String, userLevel: Int) async throws -> [Word] {
        do {
            try await invokeEnsureDailyWordsCallable(date: date, category: category, userLevel: userLevel)
        } catch {
            print("⚠️ ensureDailyWords callable failed:", error)
            throw NSError(
                domain: "DailyWordsService",
                code: -7,
                userInfo: [NSLocalizedDescriptionKey: "Couldn’t generate today’s words right now. Please try again in a moment."]
            )
        }
        let docID = Self.dailyWordsDocumentID(date: date, userLevel: userLevel)
        let ref = db.collection(collectionName).document(docID)
        let after = try await ref.getDocument()
        guard let data = after.data(),
              let arr = data["words"] as? [[String: Any]] else {
            throw NSError(
                domain: "DailyWordsService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Couldn’t load today’s words after sync. Try again."]
            )
        }
        let parsed = Self.parseWordsFromFirestore(arr)
        guard !parsed.isEmpty else {
            throw NSError(
                domain: "DailyWordsService",
                code: -5,
                userInfo: [NSLocalizedDescriptionKey: "Today’s words are incomplete. Try again."]
            )
        }
        if Self.isFirestoreCacheStale(parsed: parsed, date: date, userLevel: userLevel) {
            print("⚠️ ensureDailyWords: Server words are stale/incomplete, requesting fresh enrichment.")
            return try await buildWordsFromEnrichOnly(date: date, category: category, userLevel: userLevel)
        }
        DailyWordUsageStore.shared.markUsed(words: parsed.map(\.word))
        return parsed
    }

    private func invokeEnsureDailyWordsCallable(date: String, category: String, userLevel: Int) async throws {
        _ = try await functions.httpsCallable("ensureDailyWords").call([
            "date": date,
            "category": category,
            "userLevel": userLevel
        ])
    }

    /// `manualWordsByDate` yalnızca geliştirme: Firestore’a yazılmaz, sadece zenginleştirme.
    private func buildWordsFromEnrichOnly(date: String, category: String, userLevel: Int) async throws -> [Word] {
        let cacheKey = Self.fallbackCacheKey(date: date, userLevel: userLevel)
        if let cached = Self.fallbackWordsByDate[cacheKey], !cached.isEmpty {
            return cached
        }

        let words: [Word]
        do {
            let payload = try await enrichWordsFromBackend(category: category, date: date, userLevel: userLevel)
            words = payload.words.map { item in
                let meta = Self.poolEntry(forLemma: item.word)
                return Word(
                    id: UUID.stable(from: item.word.lowercased()),
                    word: item.word,
                    definition: item.definition,
                    exampleSentence: item.exampleSentence,
                    phonetic: item.phonetic,
                    cefrLevel: meta?.cefrLevel,
                    domainTag: meta?.domainTag,
                    partOfSpeech: meta?.partOfSpeech,
                    registerTag: meta?.registerTag,
                    frequencyBand: meta?.frequencyBand
                )
            }
        } catch {
            print("⚠️ enrichWordsFromBackend failed:", error)
            throw NSError(
                domain: "DailyWordsService",
                code: -8,
                userInfo: [NSLocalizedDescriptionKey: "Couldn’t fetch word details right now. Please try again in a moment."]
            )
        }

        guard !words.isEmpty else {
            throw NSError(
                domain: "DailyWordsService",
                code: -6,
                userInfo: [NSLocalizedDescriptionKey: "No fallback words available."]
            )
        }
        DailyWordUsageStore.shared.markUsed(words: words.map(\.word))
        Self.fallbackWordsByDate[cacheKey] = words
        return words
    }

    // MARK: - Backend call (kelimeleri sen veriyorsun; AI sadece phonetic, definition, exampleSentence doldurur)

    private func enrichWordsFromBackend(category: String, date: String, userLevel: Int) async throws -> DailyWordsPayload {
        let token = try await fetchIDToken()
        let wordsToEnrich = Self.wordsForDateOrManual(date, userLevel: userLevel)
        guard wordsToEnrich.count == 3 else {
            throw NSError(
                domain: "DailyWordsService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Yeni kelime havuzu tükendi. Lütfen DailyWordPool.txt dosyasına yeni kelimeler ekleyin."]
            )
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("enrich-words"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "words": wordsToEnrich,
            "category": category
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "DailyWordsService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            // Keep raw backend payload only in debug logs; avoid showing HTML/infra output to users.
            if !msg.isEmpty {
                print("DailyWordsService backend error \(http.statusCode): \(msg)")
            }
            throw NSError(
                domain: "DailyWordsService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Backend error (\(http.statusCode))"]
            )
        }

        let payload = try JSONDecoder().decode(DailyWordsPayload.self, from: data)
        return payload
    }

    private func fetchIDToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "DailyWordsService", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "User not signed in"])
        }
        return try await user.getIDToken()
    }

    // MARK: - Parsing

    /// Firestore `words` dizisinden `Word` listesi; eksik etiketler havuzdan tamamlanır.
    static func parseWordsFromFirestore(_ arr: [[String: Any]]) -> [Word] {
        arr.compactMap { w in
            guard
                let word = w["word"] as? String,
                let definition = w["definition"] as? String,
                let example = w["exampleSentence"] as? String
            else { return nil }

            let meta = poolEntry(forLemma: word)
            let cefr = nonEmptyString(w["cefrLevel"] as? String) ?? meta?.cefrLevel
            let domain = nonEmptyString(w["domainTag"] as? String) ?? meta?.domainTag
            let pos = nonEmptyString(w["partOfSpeech"] as? String) ?? meta?.partOfSpeech
            let reg = nonEmptyString(w["registerTag"] as? String) ?? meta?.registerTag
            let fb = intFromFirestore(w["frequencyBand"]) ?? meta?.frequencyBand

            return Word(
                id: UUID.stable(from: word.lowercased()),
                word: word,
                definition: definition,
                exampleSentence: example,
                phonetic: w["phonetic"] as? String,
                cefrLevel: cefr,
                domainTag: domain,
                partOfSpeech: pos,
                registerTag: reg,
                frequencyBand: fb
            )
        }
    }

    private static func nonEmptyString(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func intFromFirestore(_ v: Any?) -> Int? {
        switch v {
        case let i as Int: return i
        case let i64 as Int64: return Int(i64)
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }

    private static func stripCodeFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // ```json ... ``` veya ``` ... ``` kaldır
        if t.hasPrefix("```") {
            // ilk satırı at
            if let firstNewline = t.firstIndex(of: "\n") {
                t = String(t[t.index(after: firstNewline)...])
            }
            // sondaki ``` kaldır
            if let range = t.range(of: "```", options: .backwards) {
                t.removeSubrange(range)
            }
        }

        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// text içinde başka şeyler olsa bile ilk JSON objesi/array’ini yakalar.
    /// Örn: "Here you go:\n```json\n{...}\n```" -> "{...}"
    private static func extractJSON(from s: String) -> String? {
        let t = stripCodeFences(s)

        // JSON object
        if let obj = extractBalancedJSON(t, open: "{", close: "}") { return obj }
        // JSON array
        if let arr = extractBalancedJSON(t, open: "[", close: "]") { return arr }

        return nil
    }

    private static func extractBalancedJSON(_ s: String, open: Character, close: Character) -> String? {
        guard let start = s.firstIndex(of: open) else { return nil }

        var depth = 0
        var inString = false
        var escape = false

        var i = start
        while i < s.endIndex {
            let ch = s[i]

            if inString {
                if escape { escape = false }
                else if ch == "\\" { escape = true }
                else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == open { depth += 1 }
                else if ch == close {
                    depth -= 1
                    if depth == 0 {
                        return String(s[start...i]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }

            i = s.index(after: i)
        }

        return nil
    }

}

// MARK: - DTOs

struct DailyWordsPayload: Codable {
    let category: String
    let words: [DailyWordItem]
}

struct DailyWordItem: Codable {
    let word: String
    let phonetic: String?
    let definition: String
    let exampleSentence: String
}
