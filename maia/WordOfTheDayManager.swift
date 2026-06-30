import Foundation
import Combine

@MainActor
final class WordOfTheDayManager: ObservableObject {

    @Published var currentWords: [Word] = []
    @Published var words: [Word] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let dailyService = DailyWordsService()
    /// v3: WordPack tabanlı (AI/Firestore yok). Eski kilitli cache geçersiz.
    private static let localDayWordsPrefix = "dailyWords.locked.v3."

    private var lastLoadedDayISO: String?
    private var lastLoadedUserLevel: Int?
    private var loadTask: Task<Void, Never>?

    init() {
        NotificationCenter.default.addObserver(
            forName: .pronunciationAudioURLResolved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let lemma = notification.userInfo?["lemma"] as? String,
                  let url = notification.userInfo?["audioURL"] as? String else { return }
            Task { @MainActor in
                self?.applyPronunciationAudioURL(url, lemma: lemma)
            }
        }
    }

    private static func normalizedLevel(_ userLevel: Int) -> Int {
        min(max(userLevel, 1), 11)
    }

    private static func localDayWordsKey(for dayISO: String, userLevel: Int) -> String {
        localDayWordsPrefix + dayISO + ".l\(normalizedLevel(userLevel))"
    }

    private func loadLockedWords(for dayISO: String, userLevel: Int) -> [Word]? {
        let key = Self.localDayWordsKey(for: dayISO, userLevel: userLevel)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let decoded = try? JSONDecoder().decode([Word].self, from: data) else { return nil }
        if DailyWordsService.isUsableWordSet(decoded),
           CEFRLevelMapping.isAcceptableCEFRDistribution(
               decoded,
               userLevel: userLevel,
               poolHasBand: DailyWordsService.poolHasBand
           ) {
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

    func loadWordsOfTheDay(category: VocabularyCategory = .general, userLevel: Int = 1, force: Bool = false) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadToday(category: category, userLevel: userLevel, force: force)
        }
    }

    /// Takvim günü değiştiyse (veya liste boşsa) yeniden yükle.
    func reloadIfNewCalendarDay(category: VocabularyCategory = .general, userLevel: Int = 1) {
        let today = Self.calendarDayISO()
        let level = Self.normalizedLevel(userLevel)
        let dayChanged = lastLoadedDayISO != today
        let levelChanged = lastLoadedUserLevel != nil && lastLoadedUserLevel != level

        guard dayChanged || levelChanged || currentWords.isEmpty else { return }

        loadWordsOfTheDay(
            category: category,
            userLevel: level,
            force: levelChanged && !dayChanged
        )
    }

    /// Türkiye gün sınırı (tutarlı yenileme).
    static func calendarDayISO(for date: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    func loadToday(category: VocabularyCategory = .general, userLevel: Int = 1, force: Bool = false) async {
        let date = Self.calendarDayISO()
        let level = Self.normalizedLevel(userLevel)
        let levelChanged = lastLoadedUserLevel != nil && lastLoadedUserLevel != level

        isLoading = true
        errorMessage = nil
        if force || levelChanged {
            currentWords = []
            words = []
        }

        if Task.isCancelled { return }

        // Hard lock: aynı gün + aynı seviye; offline başlangıçta ekran hızlıca görünür.
        if !force, !levelChanged,
           let locked = loadLockedWords(for: date, userLevel: level), !locked.isEmpty {
            applyLoadedWords(locked, date: date, userLevel: level)
            return
        }

        do {
            if Task.isCancelled { return }

            let generated = try await dailyService.ensureDailyWords(
                date: date,
                category: category.rawValue,
                userLevel: level
            )

            if Task.isCancelled { return }

            applyLoadedWords(generated, date: date, userLevel: level)
        } catch {
            if Task.isCancelled { return }
            print("🔥 loadToday error:", error)
            currentWords = []
            words = []
            errorMessage = Self.friendlyLoadError(error)
            isLoading = false
        }
    }

    private func applyLoadedWords(_ loaded: [Word], date: String, userLevel: Int) {
        currentWords = loaded
        words = loaded
        saveLockedWords(loaded, for: date, userLevel: userLevel)
        lastLoadedDayISO = date
        lastLoadedUserLevel = userLevel
        isLoading = false
        WordPronunciationService.shared.prefetch(words: loaded)
    }

    private func applyPronunciationAudioURL(_ url: String, lemma: String) {
        let patch: ([Word]) -> [Word] = { list in
            list.map { item in
                guard WordPronunciationService.normalizeLemma(item.word) == lemma,
                      item.pronunciationAudioURL != url else { return item }
                return item.withPronunciationAudioURL(url)
            }
        }
        let updated = patch(currentWords)
        guard updated != currentWords else { return }
        currentWords = updated
        words = updated
        if let day = lastLoadedDayISO, let level = lastLoadedUserLevel {
            saveLockedWords(updated, for: day, userLevel: level)
        }
    }

    /// Hata metnini kullanıcıya sade gösterir.
    private static func friendlyLoadError(_ error: Error) -> String {
        if let nsError = error as NSError?,
           nsError.domain == "DailyWordsService",
           nsError.code == -10 || nsError.code == -11 {
            return error.localizedDescription
        }
        let lower = error.localizedDescription.lowercased()
        if lower.contains("offline") || lower.contains("client is offline") {
            return String(localized: "Couldn't load today's words. Check your connection, then tap Try Again.")
        }
        return error.localizedDescription
    }
}
