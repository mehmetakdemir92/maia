//
//  ReviewListView.swift
//  maia
//
//  Bugün tekrarlanacak kelimeler: SM-2 due listesi, nextDueAt'a göre (en gecikmiş önce) sıralı.
//

import SwiftUI

struct ReviewListView: View {
    @EnvironmentObject var diaryManager: DiaryManager
    @EnvironmentObject var progressManager: WordProgressManager
    @Environment(\.dismiss) var dismiss

    let wordManager: WordOfTheDayManager
    var onSelectWord: (Word) -> Void

    /// Diary + günün kelimelerinden tekilleştirilmiş; sadece tekrar zamanı gelmiş olanlar, nextDueAt'a göre sıralı (en gecikmiş önce).
    private var dueWords: [Word] {
        let fromDiary = diaryManager.entries.flatMap { $0.words }
        let all = fromDiary + wordManager.words   // ✅ değişti

        let unique = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values

        return unique
            .filter { progressManager.isDue(for: $0.id) }
            .sorted {
                progressManager.getProgress(for: $0.id).nextDueAt <
                progressManager.getProgress(for: $1.id).nextDueAt
            }
    }

    /// Öğrenilmiş tüm kelimeler (diary + günün kelimeleri, tekilleştirilmiş).
    private var learnedWords: [Word] {
        let fromDiary = diaryManager.entries.flatMap { $0.words }
        let all = fromDiary + wordManager.words   // ✅ değişti

        return Array(Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GlassSceneBackground()
                Group {
                    if dueWords.isEmpty {
                        VStack(spacing: 24) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.green)

                            Text("You're all caught up!")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("Right now there are no words that need review. Keep it up!")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)

                            if !learnedWords.isEmpty {
                                Button {
                                    if let randomWord = learnedWords.randomElement() {
                                        onSelectWord(randomWord)
                                        dismiss()
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "shuffle")
                                        Text("Practice with learned words")
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 20)
                                    .background(AppColors.primaryButtonGradient)
                                    .cornerRadius(12)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(dueWords) { word in
                                Button {
                                    onSelectWord(word)
                                    dismiss()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(word.word)
                                                .font(.headline)
                                                .foregroundColor(.primary)

                                            if let phonetic = word.phonetic {
                                                Text(phonetic)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                            }
                                        }

                                        Spacer()

                                        PronounceButton(word: word.word, audioURL: word.pronunciationAudioURL, size: 36)

                                        Text(nextDueText(for: word))
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func nextDueText(for word: Word) -> String {
        let next = progressManager.getProgress(for: word.id).nextDueAt
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        return formatter.string(from: next)
    }
}
