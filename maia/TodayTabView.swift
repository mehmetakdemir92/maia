//
//  TodayTabView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI
import AVFoundation

struct TodayTabView: View {
    @StateObject private var wordManager = WordOfTheDayManager()

    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var diaryManager: DiaryManager
    @EnvironmentObject var progressManager: WordProgressManager

    @State private var speechSynthesizer = AVSpeechSynthesizer()

    @State private var showingSettings = false
    @State private var showingPremiumPaywall = false
    @State private var navigationPath = NavigationPath()
    @State private var loggedWordIDs: Set<UUID> = []

    // wordId -> en fazla 2 AI cümlesi
    @State private var generatedExamples: [UUID: [String]] = [:]
    @State private var generatingForWordId: UUID? = nil

    private let exampleGenerator = ExampleGenerator()

    private static let generatedExamplesKey = "generatedExampleSentences"

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
                            ForEach(wordManager.currentWords) { word in
                                WordCardView(
                                    word: word,
                                    isPremium: userManager.isPremium,
                                    isWordQuizzedToday: diaryManager.isWordQuizzed(word, for: Date()),
                                    generatedExamples: generatedExamples[word.id] ?? [],
                                    isGenerating: generatingForWordId == word.id,
                                    onPronounce: { pronounceWord(word.word) },
                                    onQuiz: {
                                        navigationPath.append(word.id)
                                    },
                                    onGenerateMore: {
                                        handleGenerateExample(for: word)
                                    }
                                )
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !userManager.isPremium {
                    BannerAdView(adUnitID: AdMobConfig.bannerAdUnitID)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .onAppear {
                            TrackingPermission.requestIfNeededOnce()
                        }
                }
            }
            .onAppear {
                reloadIfCalendarDayChanged()
                loadGeneratedExamples()
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
            .onChange(of: userManager.selectedCategory) { _, _ in
                reloadWords()
            }
            .onChange(of: userManager.isPremium) { _, _ in
                reloadWords()
            }
            .onChange(of: userManager.userLevel) { _, _ in
                reloadWords()
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

        }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.white.opacity(0.95))
            }
        }
    }

    // MARK: - Data / Actions

    private func reloadIfCalendarDayChanged() {
        let category = userManager.isPremium ? userManager.selectedCategory : .general
        wordManager.reloadIfNewCalendarDay(category: category, userLevel: userManager.userLevel)
    }

    private func reloadWords() {
        let category = userManager.isPremium ? userManager.selectedCategory : .general
        wordManager.loadWordsOfTheDay(category: category, userLevel: userManager.userLevel)
    }

    /// Kelimeyi currentWords veya diary'den bulur (Review'dan quiz açılırken gerekir).
    private func word(for wordId: UUID) -> Word? {
        wordManager.currentWords.first { $0.id == wordId }
        ?? diaryManager.entries.flatMap { $0.words }.first { $0.id == wordId }
    }

    private func pronounceWord(_ word: String) {
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        speechSynthesizer.speak(utterance)
    }

    private func loadGeneratedExamples() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.generatedExamplesKey),
            let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }

        generatedExamples = Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            guard let id = UUID(uuidString: key) else { return nil }
            return (id, value)
        })
    }

    private func saveGeneratedExamples() {
        let raw = Dictionary(uniqueKeysWithValues: generatedExamples.map { ($0.key.uuidString, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        UserDefaults.standard.set(data, forKey: Self.generatedExamplesKey)
    }

    private func handleGenerateExample(for word: Word) {
        guard userManager.isPremium else {
            showingPremiumPaywall = true
            return
        }

        let current = generatedExamples[word.id] ?? []
        guard current.count < 2 else { return }

        generatingForWordId = word.id

        Task {
            do {
                let avoid = [word.exampleSentence] + current
                let newExample = try await exampleGenerator.generateExample(
                    for: word,
                    avoidingSentences: avoid,
                    useAlternateModel: !current.isEmpty
                )
                await MainActor.run {
                    generatedExamples[word.id] = current + [newExample]
                    generatingForWordId = nil
                    saveGeneratedExamples()
                }
            } catch {
                await MainActor.run {
                    generatingForWordId = nil
                    print("Error generating example: \(error.localizedDescription)")
                }
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

    let onPronounce: () -> Void
    let onQuiz: () -> Void
    let onGenerateMore: () -> Void

    private var allSentences: [String] {
        // word.exampleSentence2/3 dosyadan gelebilir
        let second = generatedExamples.indices.contains(0) ? generatedExamples[0] : word.exampleSentence2
        let third  = generatedExamples.indices.contains(1) ? generatedExamples[1] : word.exampleSentence3

        return [word.exampleSentence] + [second, third].compactMap { $0 }
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

            Button(action: onPronounce) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.title2)
                    .foregroundColor(AppColors.glassCardTitle)
                    .frame(width: pronounceButtonSide, height: pronounceButtonSide)
                    .background(.thinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(AppColors.glassCardTitle.opacity(0.22), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
            }
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

        } else if isGenerating {
            HStack(spacing: 4) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primaryButton))
                    .scaleEffect(0.8)
                Text("Generate More")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(AppColors.glassCardMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.glassCardTitle.opacity(0.06))
            .cornerRadius(8)

        } else if isPremium {
            Button(action: onGenerateMore) {
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
            .buttonStyle(.plain)

        } else {
            Button(action: onGenerateMore) {
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
            .buttonStyle(.plain)
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
                Button(action: onQuiz) {
                    HStack {
                        Image(systemName: "book.fill")
                        Text("Take Quiz")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(AppColors.primaryButtonGradient)
                    .cornerRadius(10)
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
