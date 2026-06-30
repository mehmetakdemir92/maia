//
//  TodayTabView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI
import Combine

struct TodayTabView: View {
    @StateObject private var wordManager = WordOfTheDayManager()

    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var diaryManager: DiaryManager
    @EnvironmentObject var progressManager: WordProgressManager

    @State private var showingSettings = false
    @State private var showingPremiumPaywall = false
    @State private var navigationPath = NavigationPath()
    @State private var loggedWordIDs: Set<UUID> = []

    /// wordId -> en fazla 2 ek örnek cümle (WordPack JSON'undan; hiç AI yok).
    @State private var revealedExtraExamples: [UUID: [String]] = [:]
    @State private var generatingWordIds: Set<UUID> = []
    @State private var startingQuizWordId: UUID?

    private static let revealedExamplesKey = "revealedExtraExampleSentences"
    private static let rippleMinDurationNs: UInt64 = 450_000_000
    private static let quizRippleLeadNs: UInt64 = 650_000_000

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                GlassSceneBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header

                        if wordManager.isLoading && wordManager.currentWords.isEmpty {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else if wordManager.currentWords.isEmpty {
                            VStack(spacing: 14) {
                                Text(wordManager.errorMessage ?? String(localized: "Today's words couldn't be loaded."))
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.92))
                                    .multilineTextAlignment(.center)
                                Button {
                                    reloadWords()
                                } label: {
                                    Text(String(localized: "Try Again"))
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                        } else {
                            let words = wordManager.currentWords
                            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                                WordCardView(
                                    word: word,
                                    isPremium: userManager.isPremium,
                                    isWordQuizzedToday: diaryManager.isWordQuizzed(word, for: Date()),
                                    generatedExamples: revealedExtraExamples[word.id] ?? [],
                                    isGenerating: generatingWordIds.contains(word.id),
                                    isStartingQuiz: startingQuizWordId == word.id,
                                    onQuiz: {
                                        startQuiz(for: word)
                                    },
                                    onGenerateMore: {
                                        handleGenerateExample(for: word)
                                    }
                                )

                                if !userManager.isPremium, index == 0 {
                                    InlineBannerAdRow(
                                        placement: AppAnalyticsPlacement.todayInlineBannerAfterFirst
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { toolbar }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingPremiumPaywall) {
                PremiumPaywallView(placement: AppAnalyticsPlacement.todayGenerateMore)
                    .environmentObject(userManager)
            }
            .navigationDestination(for: UUID.self) { wordId in
                if let word = word(for: wordId) {
                    QuizView(word: word)
                }
            }
            .onAppear {
                reloadIfCalendarDayChanged()
                loadRevealedExamples()
            }
            .onChange(of: wordManager.currentWords) { _, words in
                for word in words where !loggedWordIDs.contains(word.id) {
                    var params: [String: String] = [
                        "word_id": word.id.uuidString
                    ]
                    if let cefr = word.cefrLevel?.trimmingCharacters(in: .whitespacesAndNewlines), !cefr.isEmpty {
                        params["cefr_level"] = cefr.uppercased()
                    }
                    AppAnalytics.shared.log(AppAnalyticsEventName.dailyWordViewed, params: params)
                    loggedWordIDs.insert(word.id)
                }
            }
            .onChange(of: navigationPath.count) { _, count in
                if count == 0 {
                    startingQuizWordId = nil
                }
            }
            .onChange(of: userManager.selectedCategory) { _, _ in
                reloadWords()
            }
            .onChange(of: userManager.isPremium) { _, _ in
                reloadWords()
            }
            .onChange(of: userManager.userLevel) { oldLevel, newLevel in
                guard oldLevel != newLevel else { return }
                loggedWordIDs.removeAll()
                reloadWords(force: true)
            }
            .onChange(of: showingSettings) { _, isShowing in
                if !isShowing {
                    reloadWords(force: true)
                }
            }
        }
    }

    // MARK: - UI Pieces

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Date(), style: .date)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            }

            Spacer()

            DailyResetCountdownLabel {
                reloadIfCalendarDayChanged()
            }
        }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(AppColors.glassCardTitle.opacity(0.92))
            }
        }
    }

    // MARK: - Data / Actions

    private func reloadIfCalendarDayChanged() {
        let category = userManager.isPremium ? userManager.selectedCategory : .general
        wordManager.reloadIfNewCalendarDay(category: category, userLevel: userManager.userLevel)
    }

    private func reloadWords(force: Bool = false) {
        let category = userManager.isPremium ? userManager.selectedCategory : .general
        wordManager.loadWordsOfTheDay(
            category: category,
            userLevel: userManager.userLevel,
            force: force
        )
    }

    /// Kelimeyi currentWords veya diary'den bulur (Review'dan quiz açılırken gerekir).
    private func word(for wordId: UUID) -> Word? {
        wordManager.currentWords.first { $0.id == wordId }
        ?? diaryManager.entries.flatMap { $0.words }.first { $0.id == wordId }
    }

    private func loadRevealedExamples() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.revealedExamplesKey),
            let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }

        revealedExtraExamples = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let id = UUID(uuidString: key) else { return nil }
            return (id, value)
        })
    }

    private func saveRevealedExamples() {
        let raw = Dictionary(uniqueKeysWithValues: revealedExtraExamples.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        UserDefaults.standard.set(data, forKey: Self.revealedExamplesKey)
    }

    /// Generate More: WordPack JSON'undaki 2./3. cümleleri sırayla açar.
    private func handleGenerateExample(for word: Word) {
        guard userManager.isPremium else {
            showingPremiumPaywall = true
            return
        }

        let current = revealedExtraExamples[word.id] ?? []
        guard current.count < 2, !generatingWordIds.contains(word.id) else { return }

        generatingWordIds.insert(word.id)

        Task {
            async let minDelay: Void = Task.sleep(nanoseconds: Self.rippleMinDurationNs)
            let date = WordOfTheDayManager.calendarDayISO()
            let extras = nextExtraExamples(for: word, date: date, alreadyShown: current)
            _ = try? await minDelay

            await MainActor.run {
                if !extras.isEmpty {
                    let updated = current + Array(extras.prefix(1))
                    revealedExtraExamples[word.id] = updated
                    saveRevealedExamples()
                }
                generatingWordIds.remove(word.id)
            }
        }
    }

    private func startQuiz(for word: Word) {
        guard startingQuizWordId == nil else { return }
        startingQuizWordId = word.id

        Task {
            // Dalga animasyonu görünsün diye navigasyondan önce bekle
            try? await Task.sleep(nanoseconds: Self.quizRippleLeadNs)
            await MainActor.run {
                navigationPath.append(word.id)
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                if startingQuizWordId == word.id {
                    startingQuizWordId = nil
                }
            }
        }
    }

    /// Sırada hangi yedek cümle gösterilecek? Önce Word'ün üzerindeki 2/3, sonra
    /// store'dan ham WordPack examples (yine deduplike eder).
    private func nextExtraExamples(for word: Word, date: String, alreadyShown: [String]) -> [String] {
        let known = ([word.exampleSentence2, word.exampleSentence3].compactMap { $0 })
            + DailyWordsService.extraExamples(forWord: word.word, date: date)
        var seen = Set<String>()
        seen.insert(word.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        for shown in alreadyShown {
            seen.insert(shown.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        var results: [String] = []
        for candidate in known {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.lowercased()
            guard !trimmed.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(trimmed)
        }
        return results
    }
}

// MARK: - Daily Reset Countdown

/// Her saniye güncellenen "Resets in Xh Ym" etiketi.
/// Kelimelerin yenilendiği saat dilimine (Europe/Istanbul gece 12) sayar; sıfıra ulaşınca `onReset`'i çağırır.
private struct DailyResetCountdownLabel: View {
    let onReset: () -> Void

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        return cal
    }()

    private var nextMidnight: Date {
        let startOfToday = Self.calendar.startOfDay(for: now)
        return Self.calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now
    }

    private var remaining: TimeInterval {
        max(0, nextMidnight.timeIntervalSince(now))
    }

    private var formatted: String {
        let total = Int(remaining)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        }
        if m > 0 {
            return String(format: "%dm %02ds", m, s)
        }
        return String(format: "%ds", s)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
                .font(.caption2)
            Text("Resets in \(formatted)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .foregroundColor(.white.opacity(0.85))
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        }
        .onReceive(timer) { value in
            let target = nextMidnight
            let previous = now
            now = value
            if previous < target, value >= target {
                onReset()
            }
        }
    }
}

// MARK: - Word Card

private struct WordCardView: View {
    private let pronounceButtonSide: CGFloat = 50

    let word: Word
    let isPremium: Bool
    let isWordQuizzedToday: Bool

    /// Sadece AI ile üretilmiş (en fazla 2) cümleler
    let generatedExamples: [String]
    let isGenerating: Bool
    let isStartingQuiz: Bool

    let onQuiz: () -> Void
    let onGenerateMore: () -> Void

    private var allSentences: [String] {
        // Premium kullanıcı için bile 2./3. cümleler otomatik gösterilmez:
        // yalnızca "Generate More" tuşuyla açtıkları (generatedExamples) eklenir.
        // word.exampleSentence2/3 yalnızca nextExtraExamples içinde, butona basıldığında kaynak olarak kullanılır.
        return [word.exampleSentence] + generatedExamples
    }

    private var extraCount: Int {
        max(0, allSentences.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            topRow

            Divider()
                .background(AppColors.glassCardTitle.opacity(0.15))

            definition

            Divider()
                .background(AppColors.glassCardTitle.opacity(0.15))

            examples

            Divider()
                .background(AppColors.glassCardTitle.opacity(0.15))

            quizSection
        }
        .padding(24)
        .wordCardGlassBackground(cornerRadius: 22)
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(word.word)
                    .font(.system(size: 36, weight: .bold))
                    .glassCardWordTitle()

                if word.phonetic != nil
                    || !(word.cefrLevel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    HStack(alignment: .center, spacing: 10) {
                        if let phonetic = word.phonetic {
                            Text(phonetic)
                                .glassCardPhonetic()
                                .multilineTextAlignment(.leading)
                        }

                        if let pos = word.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                           !pos.isEmpty {
                            Text(pos)
                                .font(.subheadline)
                                .italic()
                                .foregroundColor(.black.opacity(0.78))
                        }

                        if let cefr = word.cefrLevel?.trimmingCharacters(in: .whitespacesAndNewlines), !cefr.isEmpty {
                            let cefrCorner: CGFloat = 6
                            Text(cefr.uppercased())
                                .font(.subheadline.weight(.semibold).width(.condensed))
                                .foregroundColor(AppColors.glassCardMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: cefrCorner, style: .continuous)
                                        .fill(AppColors.glassCardTitle.opacity(0.08))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: cefrCorner, style: .continuous)
                                        .strokeBorder(AppColors.glassCardTitle.opacity(0.14), lineWidth: 1)
                                }
                        }

                        Spacer(minLength: 0)
                    }
                }
            }

            Spacer(minLength: 8)

            PronounceButton(
                word: word.word,
                audioURL: word.pronunciationAudioURL,
                size: pronounceButtonSide
            )
        }
    }

    private var definition: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Definition")
                .glassCardSectionLabel()

            Text(word.definition)
                .font(.body.weight(.medium))
                .glassCardReadableBody()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Example")
                    .glassCardSectionLabel()

                Spacer()

                exampleActionChip
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(allSentences.enumerated()), id: \.offset) { _, sentence in
                    HStack(alignment: .top, spacing: 10) {
                        Text("•")
                            .font(.body.weight(.bold))
                            .foregroundColor(AppColors.glassCardBody)
                            .frame(width: 14, alignment: .leading)
                            .padding(.top, 1)

                        Text(sentence)
                            .font(.body.weight(.medium))
                            .italic()
                            .foregroundColor(AppColors.glassCardBody)
                            .lineSpacing(3)
                            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: allSentences.count)
        }
    }

    @ViewBuilder
    private var exampleActionChip: some View {
        if extraCount >= 2 {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                Text("Generated")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(AppColors.glassCardMuted)

        } else if isPremium {
            RippleLoadingButton(
                isLoading: isGenerating,
                cornerRadius: 10,
                rippleStyle: .onDark,
                action: onGenerateMore
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                    Text("Generate More")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppColors.primaryButtonGradient)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            }

        } else {
            RippleLoadingButton(
                isLoading: isGenerating,
                cornerRadius: 8,
                rippleStyle: .onLight,
                action: onGenerateMore
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                    Text("Generate More")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(AppColors.glassCardMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColors.glassCardTitle.opacity(0.06))
                .cornerRadius(8)
            }
        }
    }

    private var quizSection: some View {
        HStack {
            Spacer()

            if isWordQuizzedToday {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("You learned it!")
                        .font(.headline)
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(10)
            } else {
                RippleLoadingButton(
                    isLoading: isStartingQuiz,
                    cornerRadius: 10,
                    rippleStyle: .onDark,
                    action: onQuiz
                ) {
                    HStack {
                        Image(systemName: "book.fill")
                        Text("Take Quiz")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(AppColors.primaryButtonGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    TodayTabView()
        .environmentObject(StreakManager())
        .environmentObject(UserManager())
        .environmentObject(DiaryManager())
        .environmentObject(WordProgressManager())
}
