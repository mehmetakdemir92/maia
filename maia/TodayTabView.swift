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
    @EnvironmentObject var learningLanguageManager: LearningLanguageManager

    @State private var showingSettings = false
    @State private var showingPremiumPaywall = false
    @State private var navigationPath = NavigationPath()
    @State private var loggedWordIDs: Set<UUID> = []

    /// wordId -> up to 2 extra example sentences from the curriculum spine (no AI).
    @State private var revealedExtraExamples: [UUID: [String]] = [:]
    @State private var generatingWordIds: Set<UUID> = []
    @State private var isStartingQuiz = false
    @State private var isShowingQuiz = false
    @State private var pendingSessionItems: [QuizSessionItem] = []
    @State private var pendingSessionNow: Date = Date()

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
                                    generatedExamples: revealedExtraExamples[word.id] ?? [],
                                    isGenerating: generatingWordIds.contains(word.id),
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

                            todaysQuizSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingPremiumPaywall) {
                PremiumPaywallView(placement: AppAnalyticsPlacement.todayGenerateMore)
                    .environmentObject(userManager)
            }
            .navigationDestination(isPresented: $isShowingQuiz) {
                QuizView(items: pendingSessionItems, now: pendingSessionNow) {
                    Task { await wordManager.completeCurrentSlot() }
                }
            }
            .onAppear {
                reloadIfCalendarDayChanged()
                loadRevealedExamples()
            }
            .onChange(of: wordManager.currentWords) { _, words in
                for word in words where !loggedWordIDs.contains(word.id) {
                    var params: [String: String] = [
                        "word_id": word.id.uuidString,
                        AppAnalyticsParam.learningLanguage: word.learningLanguage.code
                    ]
                    if let cefr = word.cefrLevel?.trimmingCharacters(in: .whitespacesAndNewlines), !cefr.isEmpty {
                        params[AppAnalyticsParam.cefrLevel] = cefr.uppercased()
                    }
                    AppAnalytics.shared.log(AppAnalyticsEventName.dailyWordViewed, params: params)
                    loggedWordIDs.insert(word.id)
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
            .onChange(of: learningLanguageManager.selected) { oldLanguage, newLanguage in
                guard oldLanguage != newLanguage else { return }
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
        HStack(spacing: 10) {
            learningLanguageFlags

            Spacer(minLength: 8)

            if !wordManager.isSlotUnlocked {
                DailyResetCountdownLabel {
                    reloadIfCalendarDayChanged()
                }
            }

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(AppColors.glassCardTitle.opacity(0.92))
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
                            }
                            .glassMaterialIgnoresSystemColorScheme()
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Settings"))
        }
    }

    /// UK / Germany flags — selected is vivid, the other is faded.
    private var learningLanguageFlags: some View {
        HStack(spacing: 8) {
            ForEach(LearningLanguage.allCases) { language in
                let isSelected = learningLanguageManager.selected == language
                Button {
                    learningLanguageManager.setSelected(language)
                } label: {
                    LearningLanguageFlagIcon(language: language, isSelected: isSelected)
                        .frame(width: 30, height: 20)
                        .opacity(isSelected ? 1.0 : 0.38)
                        .saturation(isSelected ? 1.0 : 0.35)
                        .scaleEffect(isSelected ? 1.0 : 0.94)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                        .accessibilityLabel(language.title)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.18), value: isSelected)
            }
        }
    }

    // MARK: - Today's Quiz

    @ViewBuilder
    private var todaysQuizSection: some View {
        if wordManager.isSlotUnlocked {
            RippleLoadingButton(
                isLoading: isStartingQuiz,
                cornerRadius: 14,
                rippleStyle: .onDark,
                action: startTodaysQuiz
            ) {
                HStack {
                    Image(systemName: "book.fill")
                    Text(String(localized: "Take Today's Quiz"))
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.primaryButtonGradient)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(String(localized: "You've finished today's quiz. Come back tomorrow!"))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    /// Generate More: reveals 2nd/3rd authored sentences in order.
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
            let extras = nextExtraExamples(for: word, alreadyShown: current)
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

    /// Builds today's session (slot's new words + whatever spaced repetition
    /// says is due) and navigates once the ripple animation has played.
    ///
    /// Uses `trustedNow()`, not the device clock, for both picking which
    /// reviews are due and (later, in QuizView) stamping their new due dates —
    /// otherwise a clock pushed forward makes reviews appear due before they
    /// really are, or a clock pushed forward then back plants a bogus future
    /// `nextDueAt`. Fetched once here and reused for the whole session so a
    /// clock change mid-quiz can't affect the write either.
    private func startTodaysQuiz() {
        guard !isStartingQuiz, wordManager.isSlotUnlocked else { return }
        isStartingQuiz = true

        Task {
            let trustedNow = await CurriculumStateManager.trustedNow()

            let items = QuizSessionBuilder.build(
                newWords: wordManager.currentWords,
                reviewCandidates: diaryManager.entries.flatMap(\.words),
                progress: progressManager,
                now: trustedNow,
                seed: "\(wordManager.currentSlotIndex)"
            )
            guard !items.isEmpty else {
                await MainActor.run { isStartingQuiz = false }
                return
            }

            try? await Task.sleep(nanoseconds: Self.quizRippleLeadNs)
            await MainActor.run {
                pendingSessionItems = items
                pendingSessionNow = trustedNow
                isShowingQuiz = true
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                isStartingQuiz = false
            }
        }
    }

    /// Next extra sentence to reveal: Word.exampleSentence2/3 first, then the
    /// remaining authored examples from the spine (deduplicated).
    private func nextExtraExamples(for word: Word, alreadyShown: [String]) -> [String] {
        let known = ([word.exampleSentence2, word.exampleSentence3].compactMap { $0 })
            + CurriculumService.extraExamples(forWord: word.word)
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

/// "Resets in Xh Ym" label, updated every second.
/// Counts down to the same study-day boundary that gates the next slot
/// (the learner's own timezone, shifted to start at `CurriculumStateManager.dayResetHour`).
private struct DailyResetCountdownLabel: View {
    let onReset: () -> Void

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var nextReset: Date {
        let todayStart = CurriculumStateManager.studyDayStart(for: now)
        return Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? now
    }

    private var remaining: TimeInterval {
        max(0, nextReset.timeIntervalSince(now))
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
            let target = nextReset
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

    @EnvironmentObject private var languageManager: AppLanguageManager

    let word: Word
    let isPremium: Bool

    /// Only AI-generated sentences (up to 2)
    let generatedExamples: [String]
    let isGenerating: Bool

    let onGenerateMore: () -> Void

    private var allSentences: [String] {
        // Extra sentences 2/3 are not shown automatically, even for premium:
        // only sentences revealed via Generate More (generatedExamples) are added.
        // word.exampleSentence2/3 are used as sources in nextExtraExamples when the button is tapped.
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
        }
        .padding(24)
        .wordCardGlassBackground(cornerRadius: 22)
    }

    private var topRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(word.word)
                    .font(.system(size: 36, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .allowsTightening(true)
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
                size: pronounceButtonSide,
                languageCode: word.languageCode
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

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(allSentences.enumerated()), id: \.offset) { _, sentence in
                    ExampleSentenceRow(
                        sentence: sentence,
                        gloss: word.gloss(
                            forExample: sentence,
                            preferredLanguageCode: languageManager.preferredExampleGlossCode
                        ),
                        highlightWord: word.word,
                        learningLanguage: word.learningLanguage
                    )
                }
            }
            .animation(.easeInOut(duration: 0.3), value: allSentences.count)
            .id(languageManager.refreshID)
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

}

// MARK: - Preview

#Preview {
    TodayTabView()
        .environmentObject(StreakManager())
        .environmentObject(UserManager())
        .environmentObject(DiaryManager())
        .environmentObject(WordProgressManager())
}
