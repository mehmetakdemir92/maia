//
//  WordOfTheDayView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI
import AVFoundation

struct WordOfTheDayView: View {
    @StateObject private var wordManager = WordOfTheDayManager()
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var userManager: UserManager
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var generatedExamples: [UUID: String] = [:] // wordId -> generated example
    @State private var generatingForWordId: UUID? = nil
    @State private var showingPremiumPaywall = false
    private let exampleGenerator = ExampleGenerator()
    
    var body: some View {
        ZStack {
            GlassSceneBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Word of the Day")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)

                        Text(Date(), style: .date)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.88))
                    }

                    if !wordManager.words.isEmpty {
                        ForEach(wordManager.words) { word in
                            // Word Card
                            VStack(alignment: .leading, spacing: 20) {
                                // Word and Pronunciation Button
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(word.word)
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)

                                        if let phonetic = word.phonetic {
                                            Text(phonetic)
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.78))
                                                .italic()
                                        }
                                    }

                                    Spacer()

                                    // Pronunciation Button
                                    Button(action: {
                                        pronounceWord(word.word)
                                    }) {
                                        Image(systemName: "speaker.wave.2.fill")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .padding(12)
                                            .background(.thinMaterial, in: Circle())
                                            .overlay {
                                                Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                                            }
                                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                                    }
                                }

                                Divider()
                                    .background(AppColors.glassCardTitle.opacity(0.15))

                                // Definition
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Definition")
                                        .glassCardSectionLabel()

                                    Text(word.definition)
                                        .font(.body.weight(.medium))
                                        .glassCardReadableBody()
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Divider()
                                    .background(AppColors.glassCardTitle.opacity(0.15))

                                // Example Sentence
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Example")
                                            .glassCardSectionLabel()

                                        Spacer()

                                        // Suggestion butonu (örnek cümle önerisi)
                                        Button(action: {
                                            handleGenerateExample(for: word)
                                        }) {
                                            HStack(spacing: 6) {
                                                if generatingForWordId == word.id {
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primaryButton))
                                                        .scaleEffect(0.8)
                                                } else {
                                                    Image(systemName: "wand.and.stars")
                                                        .font(.caption)
                                                }
                                                Text("Generate More")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .foregroundColor(userManager.isPremium ? AppColors.primaryButton : AppColors.glassCardMuted)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background {
                                                Group {
                                                    if userManager.isPremium {
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .fill(.thinMaterial)
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .fill(AppColors.glassCardTitle.opacity(0.06))
                                                    }
                                                }
                                            }
                                            .overlay {
                                                if userManager.isPremium {
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .strokeBorder(AppColors.primaryButton.opacity(0.35), lineWidth: 0.5)
                                                }
                                            }
                                        }
                                        .disabled(userManager.isPremium && generatingForWordId == word.id)
                                    }

                                    // Show generated example if available, otherwise show original
                                    let displayExample = generatedExamples[word.id] ?? word.exampleSentence
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("•")
                                            .font(.body.weight(.bold))
                                            .foregroundColor(AppColors.glassCardBody)
                                            .frame(width: 14, alignment: .leading)
                                            .padding(.top, 1)

                                        Text(displayExample)
                                            .font(.body.weight(.medium))
                                            .italic()
                                            .foregroundColor(AppColors.glassCardBody)
                                            .lineSpacing(3)
                                            .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .animation(.easeInOut(duration: 0.3), value: displayExample)
                                }
                            }
                            .padding(24)
                            .wordCardGlassBackground(cornerRadius: 22)
                        }
                    } else {
                        // Loading state
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingPremiumPaywall) {
            PremiumPaywallView(placement: AppAnalyticsPlacement.wordOfDayGenerateMore)
                .environmentObject(userManager)
        }
        .task {
            await wordManager.loadToday(category: .general, userLevel: userManager.userLevel)
        }
        .onChange(of: userManager.userLevel) { _, newLevel in
            Task {
                await wordManager.loadToday(category: .general, userLevel: newLevel)
            }
        }
    }
    
    private func pronounceWord(_ word: String) {
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        speechSynthesizer.speak(utterance)
    }
    
    private func handleGenerateExample(for word: Word) {
        // Premium kontrolü
        guard userManager.isPremium else {
            showingPremiumPaywall = true
            return
        }
        
        // Generate işlemini başlat
        generatingForWordId = word.id
        
        Task {
            do {
                let newExample = try await exampleGenerator.generateExample(
                    for: word,
                    avoidingSentences: [word.exampleSentence],
                    useAlternateModel: false
                )
                await MainActor.run {
                    generatedExamples[word.id] = newExample
                    generatingForWordId = nil
                }
            } catch {
                await MainActor.run {
                    generatingForWordId = nil
                    // Hata durumunda kullanıcıya bilgi verilebilir
                    print("Error generating example: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    WordOfTheDayView()
        .environmentObject(UserManager())
}

