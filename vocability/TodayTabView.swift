//
//  TodayTabView.swift
//  vocability
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
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var selectedWordForQuiz: Word? = nil
    @State private var showingQuiz = false
    @State private var navigationPath = NavigationPath()
    @State private var showingPremiumAlert = false
    @State private var showingSettings = false
    @State private var generatedExamples: [UUID: String] = [:] // wordId -> generated example
    @State private var generatingForWordId: UUID? = nil
    private let exampleGenerator = ExampleGenerator()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Date(), style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .subtleStrokeText()
                        }
                        
                        Spacer()
                    }
                    
                    if !wordManager.currentWords.isEmpty {
                        // Display 3 word cards
                        ForEach(wordManager.currentWords) { word in
                            // Word Card
                            VStack(alignment: .leading, spacing: 20) {
                                // Word and Pronunciation Button
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(word.word)
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(AppColors.primaryText)
                                        
                                        if let phonetic = word.phonetic {
                                            Text(phonetic)
                                                .font(.subheadline)
                                                .foregroundColor(AppColors.secondaryText)
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
                                            .foregroundColor(AppColors.primaryText)
                                            .padding(12)
                                            .background(AppColors.primaryText.opacity(0.1))
                                            .clipShape(Circle())
                                    }
                                }
                                
                                Divider()
                                    .background(AppColors.secondaryText.opacity(0.2))
                                
                                // Definition
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Definition")
                                        .font(.headline)
                                        .foregroundColor(AppColors.secondaryText)
                                    
                                    Text(word.definition)
                                        .font(.body)
                                        .foregroundColor(AppColors.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                
                                Divider()
                                    .background(AppColors.secondaryText.opacity(0.2))
                                
                                // Example Sentence
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Example")
                                            .font(.headline)
                                            .foregroundColor(AppColors.secondaryText)
                                        
                                        Spacer()
                                        
                                        // Generate New Example Button (Premium)
                                        Button(action: {
                                            handleGenerateExample(for: word)
                                        }) {
                                            HStack(spacing: 4) {
                                                if generatingForWordId == word.id {
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle())
                                                        .scaleEffect(0.8)
                                                } else {
                                                    Image(systemName: "sparkles")
                                                        .font(.caption)
                                                }
                                                Text("Generate more")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .foregroundColor(userManager.isPremium ? AppColors.primaryButton : AppColors.secondaryText)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                userManager.isPremium 
                                                    ? AppColors.primaryButton.opacity(0.1)
                                                    : Color.gray.opacity(0.1)
                                            )
                                            .cornerRadius(8)
                                        }
                                        .disabled(generatingForWordId == word.id)
                                    }
                                    
                                    // Show generated example if available, otherwise show original
                                    let displayExample = generatedExamples[word.id] ?? word.exampleSentence
                                    Text(displayExample)
                                        .font(.body)
                                        .foregroundColor(AppColors.primaryText)
                                        .italic()
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(.leading, 8)
                                        .animation(.easeInOut(duration: 0.3), value: displayExample)
                                }
                                
                                Divider()
                                    .background(AppColors.secondaryText.opacity(0.2))
                                
                                // Quiz Button
                                HStack {
                                    Spacer()
                                    if diaryManager.isWordQuizzed(word, for: Date()) {
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
                                        Button(action: {
                                            selectedWordForQuiz = word
                                            navigationPath.append(word.id)
                                        }) {
                                            HStack {
                                                Image(systemName: "book.fill")
                                                Text("Take Quiz")
                                                    .font(.headline)
                                            }
                                            .foregroundColor(.white)
                                            .padding()
                                            .background(AppColors.primaryButton)
                                            .cornerRadius(10)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                            .padding(24)
                            .background(AppColors.cardBackground)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
                .padding()
            }
            .background(AppColors.background)
            .navigationTitle("Vocability")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.primary)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .navigationDestination(for: UUID.self) { wordId in
                if let word = wordManager.currentWords.first(where: { $0.id == wordId }) {
                    QuizView(word: word)
                }
            }
            .alert("Premium Feature", isPresented: $showingPremiumAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("This feature is available for premium users only. Upgrade to premium to generate AI-powered example sentences.")
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
            showingPremiumAlert = true
            return
        }
        
        // Generate işlemini başlat
        generatingForWordId = word.id
        
        Task {
            do {
                let newExample = try await exampleGenerator.generateExample(for: word)
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
    TodayTabView()
        .environmentObject(StreakManager())
        .environmentObject(UserManager())
}
