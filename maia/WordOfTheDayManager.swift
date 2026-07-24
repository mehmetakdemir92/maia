import Foundation
import Combine

@MainActor
final class WordOfTheDayManager: ObservableObject {

    @Published var currentWords: [Word] = []
    @Published var words: [Word] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let dailyService = DailyWordsService()
    private static let contentStampPrefix = "dailyWords.contentStamp."
    private static let localDayWordsPrefix = "dailyWords.locked.v6."

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

        if let monthKey = WordPackStore.monthKey(from: dayISO),
           let stamp = WordPackStore.contentStamp(forMonth: monthKey) {
            let stampKey = Self.contentStampPrefix + dayISO
            if UserDefaults.standard.string(forKey: stampKey) != stamp {
                UserDefaults.standard.removeObject(forKey: key)
                UserDefaults.standard.removeObject(forKey: stampKey)
                return nil
            }
        }

        if DailyWordsService.isUsableWordSet(decoded),
           CEFRLevelMapping.isAcceptableCEFRDistribution(
               decoded,
               userLevel: userLevel,
               poolHasBand: DailyWordsService.poolHasBand
           ) {
            return decoded.map { $0.withHydratedQuizzes(dayISO: dayISO) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        return nil
    }

    private func saveLockedWords(_ words: [Word], for dayISO: String, userLevel: Int) {
        let key = Self.localDayWordsKey(for: dayISO, userLevel: userLevel)
        guard let data = try? JSONEncoder().encode(words) else { return }
        UserDefaults.standard.set(data, forKey: key)
        if let monthKey = WordPackStore.monthKey(from: dayISO),
           let stamp = WordPackStore.contentStamp(forMonth: monthKey) {
            UserDefaults.standard.set(stamp, forKey: Self.contentStampPrefix + dayISO)
        }
    }

    /// Removes stale daily-word caches from older app versions (quiz JSON lived inside cache).
    static func purgeLegacyWordCaches() {
        let prefixes = [
            "dailyWords.locked.v3.",
            "dailyWords.locked.v4.",
            "dailyWords.locked.v5.",
            "dailyWords.contentStamp.",
        ]
        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            if prefixes.contains(where: { key.hasPrefix($0) }) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    func loadWordsOfTheDay(category: VocabularyCategory = .general, userLevel: Int = 1, force: Bool = false) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadToday(category: category, userLevel: userLevel, force: force)
        }
    }

    /// Reload when the calendar day changes (or list is empty).
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

    /// Turkey day boundary (consistent refresh).
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

        // Hard lock: same day + level; fast offline-first display.
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
        let hydrated = loaded.map { $0.withHydratedQuizzes(dayISO: date) }
        currentWords = hydrated
        words = hydrated
        saveLockedWords(hydrated, for: date, userLevel: userLevel)
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

    /// Simplified user-facing error text.
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
