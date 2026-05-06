import Foundation
import FirebaseFirestore
import Combine

@MainActor
final class WordOfTheDayManager: ObservableObject {

    // TodayTabView bunu bekliyor
    @Published var currentWords: [Word] = []

    // (İstersen diğer yerler kullanıyorsa kalsın)
    @Published var words: [Word] = []

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private let dailyService = DailyWordsService()
    private static let localDayWordsPrefix = "dailyWords.locked."

    /// Son başarılı yüklemede kullanılan `yyyy-MM-dd` (yeni güne geçince yeniden yükleme için)
    private var lastLoadedDayISO: String?

    private static func normalizedLevel(_ userLevel: Int) -> Int {
        min(max(userLevel, 1), 11)
    }
    
    private static func localDayWordsKey(for dayISO: String, userLevel: Int) -> String {
        localDayWordsPrefix + dayISO + ".l\(normalizedLevel(userLevel))"
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

    private func loadLockedWords(for dayISO: String, userLevel: Int) -> [Word]? {
        let key = Self.localDayWordsKey(for: dayISO, userLevel: userLevel)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let decoded = try? JSONDecoder().decode([Word].self, from: data) else { return nil }
        if Self.isUsableWordSet(decoded) {
            return decoded
        }
        UserDefaults.standard.removeObject(forKey: key)
        return nil
    }

    private func saveLockedWords(_ words: [Word], for dayISO: String, userLevel: Int) {
        let key = Self.localDayWordsKey(for: dayISO, userLevel: userLevel)
        guard let data = try? JSONEncoder().encode(words) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // TodayTabView bunu bekliyor
    func loadWordsOfTheDay(category: VocabularyCategory = .general, userLevel: Int = 1) {
        Task { await loadToday(category: category, userLevel: userLevel) }
    }

    /// Takvim günü değiştiyse (veya liste boşsa) Firestore’dan tekrar yükle. Ön plana gelince / sekmede çağır.
    func reloadIfNewCalendarDay(category: VocabularyCategory = .general, userLevel: Int = 1) {
        let today = Self.calendarDayISO()
        if lastLoadedDayISO != today {
            Task { await loadToday(category: category, userLevel: userLevel) }
            return
        }
        if currentWords.isEmpty {
            Task { await loadToday(category: category, userLevel: userLevel) }
        }
    }

    /// Firestore `dailyWords/{yyyy-MM-dd}` anahtarı — Türkiye gün sınırı (tutarlı yenileme).
    static func calendarDayISO(for date: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    func loadToday(category: VocabularyCategory = .general, userLevel: Int = 1) async {
        isLoading = true
        errorMessage = nil

        let date = Self.calendarDayISO()

        // Hard lock: same calendar day should always render same words on this device.
        if let locked = loadLockedWords(for: date, userLevel: userLevel), !locked.isEmpty {
            currentWords = locked
            words = locked
            lastLoadedDayISO = date
            isLoading = false
            return
        }

        do {
            let docID = "\(date)_l\(Self.normalizedLevel(userLevel))"
            let ref = db.collection("dailyWords").document(docID)
            // Senkron + bugünün dokümanı paralel: toplam süre ≈ max(ikisi), önceki sıralı beklemeden kısa.
            async let syncOnce: Void = DailyWordsService.syncUsedWordsFromFirestoreOnce()
            async let todayDocTask = try await ref.getDocument()
            let _ = await syncOnce
            let doc = try await todayDocTask

            // Manuel kelime seçiliyse Firestore önbelleğini atla, her seferinde ensureDailyWords ile güncelle
            let useManual = DailyWordsService.manualWordsByDate[date]?.count == 3
            if !useManual {
                if let data = doc.data(),
                   let arr = data["words"] as? [[String: Any]] {
                    let parsed = DailyWordsService.parseWordsFromFirestore(arr)
                    if Self.isUsableWordSet(parsed) {
                        DailyWordUsageStore.shared.markUsed(words: parsed.map(\.word))
                        currentWords = parsed
                        words = parsed
                        saveLockedWords(parsed, for: date, userLevel: userLevel)
                        lastLoadedDayISO = date
                        isLoading = false
                        return
                    }
                }
            }

            let generated = try await dailyService.ensureDailyWords(
                date: date,
                category: category.rawValue,
                userLevel: userLevel
            )

            currentWords = generated
            words = generated
            saveLockedWords(generated, for: date, userLevel: userLevel)
            lastLoadedDayISO = date
            isLoading = false

        } catch {
            print("🔥 loadToday error:", error)
            currentWords = []
            words = []
            errorMessage = Self.friendlyLoadError(error)
            isLoading = false
        }
    }

    /// Firestore “client is offline” vb. teknik metni kullanıcıya sade açıklamaya çevirir.
    private static func friendlyLoadError(_ error: Error) -> String {
        if let nsError = error as NSError?,
           nsError.domain == "DailyWordsService",
           (500...599).contains(nsError.code) {
            return String(localized: "Server is temporarily busy. Please tap Try Again in a few seconds.")
        }
        if let nsError = error as NSError?,
           nsError.domain == FirestoreErrorDomain,
           nsError.code == FirestoreErrorCode.internal.rawValue {
            return String(localized: "Server is temporarily busy. Please tap Try Again in a few seconds.")
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("offline") || lower.contains("client is offline") {
            return String(localized: "Firestore couldn’t connect. Check your internet connection, then tap Try Again.")
        }
        if lower == "internal"
            || lower.contains("internal error")
            || lower.contains("backend error")
            || lower.contains("<html")
            || lower.contains("503")
            || lower.contains("server error")
        {
            return String(localized: "Server is temporarily busy. Please tap Try Again in a few seconds.")
        }
        return error.localizedDescription
    }
}
