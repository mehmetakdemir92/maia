//
//  PronounceButton.swift
//  maia
//

import SwiftUI

struct PronounceButton: View {
    let word: String
    var audioURL: String?
    var size: CGFloat = 50

    @ObservedObject private var pronunciation = WordPronunciationService.shared

    private var lemma: String {
        WordPronunciationService.normalizeLemma(word)
    }

    private var isLoading: Bool {
        pronunciation.loadingLemma == lemma
    }

    var body: some View {
        Button {
            Task {
                await pronunciation.speak(word: word, preferredURL: audioURL)
            }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(AppColors.glassCardTitle)
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title2)
                        .foregroundColor(AppColors.glassCardTitle)
                }
            }
            .frame(width: size, height: size)
            .background {
                Group {
                    Circle().fill(.thinMaterial)
                }
                .glassMaterialIgnoresSystemColorScheme()
            }
            .overlay {
                Circle().strokeBorder(AppColors.glassCardTitle.opacity(0.22), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "Play pronunciation")))
    }
}
