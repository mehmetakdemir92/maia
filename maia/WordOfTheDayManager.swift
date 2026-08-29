//
//  WordOfTheDayManager.swift
//  maia
//
// Drives the Today screen off the curriculum spine.
//
// The old version resolved words from a calendar date and then LOCKED them in
// UserDefaults so the day stayed stable. None of that is needed now: a slot is
// a pure function of its index, so the same index always yields the same five
// words, offline and across devices. The locking layer is gone.
//

import Foundation
import Combine

@MainActor
final class WordOfTheDayManager: ObservableObject {

    @Published var currentWords: [Word] = []
    @Published var words: [Word] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// 1-based position in the spine the learner is on.
    @Published private(set) var currentSlotIndex: Int = 1
    /// Authoring label for the slot, if the spine provides one.
    @Published private(set) var slotTheme: String?
    /// False once today's slot is finished — the gate that creates tomorrow's return.
    @Published private(set) var isSlotUnlocked: Bool = true

    /// Where the learner stands. Exposed so views can read progress directly.
    let curriculumState: CurriculumStateManager

    private let service = CurriculumService()
    private var lastLoadedSlotIndex: Int?
    private var lastLoadedLanguage: LearningLanguage?
    private var loadTask: Task<Void, Never>?

    /// `curriculumState` is resolved in the body, not as a default argument:
    /// default arguments are evaluated in a nonisolated context, and
    /// CurriculumStateManager's initializer is main-actor isolated.
    init(curriculumState: CurriculumStateManager? = nil) {
        self.curriculumState = curriculumState ?? CurriculumStateManager()

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
        NotificationCenter.default.addObserver(
            forName: .learningLanguageChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadForLanguageChange()
            }
        }
    }

    // MARK: - Day boundary

    /// The learner's own study day. Previously pinned to Europe/Istanbul, which
    /// meant a user abroad got new words in the middle of their night — the cue
    /// has to fire on their clock, not Turkey's.
    static func calendarDayISO(for date: Date = Date()) -> String {
        CurriculumStateManager.studyDayISO(for: date)
    }

    var slotCount: Int {
        CurriculumStore.shared.slotCount(for: LearningLanguage.current)
    }

    // MARK: - Loading

    func loadWordsOfTheDay(category: VocabularyCategory = .general, force: Bool = false) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadToday(category: category, force: force)
        }
    }

    /// Re-evaluate on foreground: the gate may have opened, or the language changed.
    func reloadIfNewCalendarDay(category: VocabularyCategory = .general) {
        let languageChanged = lastLoadedLanguage != nil && lastLoadedLanguage != LearningLanguage.current
        let slotChanged = lastLoadedSlotIndex != curriculumState.currentSlotIndex
        let gateChanged = isSlotUnlocked != curriculumState.isNextSlotUnlocked

        guard languageChanged || slotChanged || gateChanged || currentWords.isEmpty else { return }

        loadWordsOfTheDay(category: category)
    }

    func loadToday(category: VocabularyCategory = .general, force: Bool = false) async {
        _ = category
        let language = LearningLanguage.current
        let count = CurriculumStore.shared.slotCount(for: language)

        isLoading = true
        errorMessage = nil

        // One-time placement: everyone enters the spine at slot 1.
        curriculumState.placeIfNeeded(slotCount: count)

        let slotIndex = curriculumState.currentSlotIndex
        // The device clock can only make the heuristic wrong in one direction
        // — a clock pushed forward makes it look unlocked early — so it only
        // needs a network round-trip to confirm THAT case. A clock nobody
        // tampered with never disagrees with itself, so the common case (gate
        // genuinely still closed) costs nothing and stays fully offline.
        if curriculumState.isNextSlotUnlocked {
            let trustedNow = await CurriculumStateManager.trustedNow()
            if Task.isCancelled { isLoading = false; return }
            isSlotUnlocked = curriculumState.isSlotUnlocked(asOf: trustedNow)
        } else {
            isSlotUnlocked = false
        }

        if force {
            currentWords = []
            words = []
        }

        if Task.isCancelled { isLoading = false; return }

        // Past the last authored slot there is nothing new to hand out. Bail
        // before asking the service, which would throw slotOutOfRange and get
        // surfaced as a load failure — the learner has finished the spine,
        // which is not an error. Reviews still flow through QuizSessionBuilder.
        if count > 0 && slotIndex > count {
            currentWords = []
            words = []
            slotTheme = nil
            errorMessage = nil
            lastLoadedSlotIndex = slotIndex
            lastLoadedLanguage = language
            isLoading = false
            return
        }

        do {
            let loaded = try await service.words(forSlot: slotIndex, language: language)
            if Task.isCancelled { return }
            currentWords = loaded
            words = loaded
            slotTheme = CurriculumStore.shared.slot(at: slotIndex, language: language)?.theme
            lastLoadedSlotIndex = slotIndex
            lastLoadedLanguage = language
            isLoading = false
            WordPronunciationService.shared.prefetch(words: loaded)
        } catch {
            if Task.isCancelled { return }
            print("🔥 loadToday error:", error)
            currentWords = []
            words = []
            slotTheme = nil
            errorMessage = Self.friendlyLoadError(error)
            isLoading = false
        }
    }

    // MARK: - Progression

    /// Call once the session for this slot is finished. Advances the pointer and
    /// closes the gate until the learner's next study day.
    func completeCurrentSlot() async {
        await curriculumState.completeCurrentSlot(slotCount: slotCount)
        isSlotUnlocked = curriculumState.isNextSlotUnlocked
    }

    /// True when the learner has run past the authored spine — reviews only.
    var hasReachedEndOfSpine: Bool {
        curriculumState.hasReachedEndOfSpine(slotCount: slotCount)
    }

    private func reloadForLanguageChange() {
        guard lastLoadedLanguage != nil, lastLoadedLanguage != LearningLanguage.current else { return }
        currentWords = []
        words = []
        slotTheme = nil
        loadWordsOfTheDay()
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
    }

    private static func friendlyLoadError(_ error: Error) -> String {
        if let serviceError = error as? CurriculumService.ServiceError {
            return serviceError.localizedDescription
        }
        let lower = error.localizedDescription.lowercased()
        if lower.contains("offline") || lower.contains("client is offline") {
            return String(localized: "Couldn't load today's words. Check your connection, then tap Try Again.")
        }
        return error.localizedDescription
    }
}
