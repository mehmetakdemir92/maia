//
//  QuizView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct QuizView: View {
    let word: Word
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var diaryManager: DiaryManager
    @EnvironmentObject var statsManager: StatsManager
    @EnvironmentObject var progressManager: WordProgressManager
    @EnvironmentObject var quizEventManager: QuizEventManager
    @StateObject private var quizManager = QuizManager()
    @Environment(\.dismiss) var dismiss
    @State private var showingResult = false
    @State private var canRetry = false
    @State private var showStreakCelebration = false
    @State private var streakScale: CGFloat = 0.5
    @State private var showingAnswerFeedback = false
    @State private var currentAnswerWasCorrect: Bool? = nil
    @State private var isAutoAdvancingAfterCorrect = false
    @State private var hasLoggedQuizCompletion = false
    
    var body: some View {
        ZStack {
            GlassSceneBackground()
            ScrollView {
            VStack(spacing: 24) {
                if !quizManager.quizCompleted {
                    // Quiz in progress
                    VStack(spacing: 20) {
                        // Progress indicator
                        HStack {
                            Text(String(format: String(localized: "Question %1$lld of %2$lld"), Int64(quizManager.currentQuestionIndex + 1), Int64(quizManager.currentQuiz.count)))
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.88))
                            Spacer()
                            Text(String(format: String(localized: "Correct: %lld"), Int64(quizManager.correctAnswers)))
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal)
                        
                        quizProgressBar
                            .padding(.horizontal)
                        
                        if !quizManager.currentQuiz.isEmpty && quizManager.currentQuestionIndex < quizManager.currentQuiz.count {
                            let question = quizManager.currentQuiz[quizManager.currentQuestionIndex]
                            
                            // Question
                            Text(question.question)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding()
                                .frame(maxWidth: .infinity)
                            
                            // Answer options
                            VStack(spacing: 12) {
                                ForEach(0..<question.options.count, id: \.self) { index in
                                    Button(action: {
                                        if showingAnswerFeedback { return }
                                        quizManager.selectAnswer(index)
                                    }) {
                                        HStack {
                                            Text(question.options[index])
                                                .font(.body)
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            if quizManager.selectedAnswerIndex == index {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(AppColors.primaryButtonGradient)
                                            }
                                        }
                                        .padding()
                                        .background(optionBackground(for: index, question: question))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                                        )
                                        .cornerRadius(10)
                                    }
                                    .disabled(showingAnswerFeedback)
                                }
                            }
                            .padding(.horizontal)

                            if showingAnswerFeedback {
                                if currentAnswerWasCorrect != true {
                                    feedbackCard(for: question)
                                        .padding(.horizontal)
                                }
                            }
                            
                            // Submit button
                            Button(action: {
                                if !showingAnswerFeedback {
                                    currentAnswerWasCorrect = quizManager.isCurrentSelectionCorrect()
                                    showingAnswerFeedback = currentAnswerWasCorrect != nil
                                    if currentAnswerWasCorrect == true {
                                        isAutoAdvancingAfterCorrect = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                                            guard showingAnswerFeedback, currentAnswerWasCorrect == true else { return }
                                            commitFeedbackAndAdvance()
                                        }
                                    }
                                } else {
                                    if currentAnswerWasCorrect != true {
                                        commitFeedbackAndAdvance()
                                    }
                                }
                            }) {
                                Text(buttonTitle)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        Group {
                                            if quizManager.selectedAnswerIndex != nil {
                                                AppColors.primaryButtonGradient
                                            } else {
                                                Color.gray
                                            }
                                        }
                                    )
                                    .cornerRadius(10)
                            }
                            .disabled(quizManager.selectedAnswerIndex == nil || isAutoAdvancingAfterCorrect)
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 16) {
                                ProgressView {
                                    Text("Loading quiz...")
                                }
                                Text("Generating questions...")
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.82))
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 620, alignment: .center)
                } else {
                    // Quiz completed - show results
                    VStack(spacing: 24) {
                        Text(quizManager.hasPassed() ? "🎉 Great Job!" : "Try Again")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(String(format: String(localized: "You got %1$lld out of %2$lld correct"), Int64(quizManager.correctAnswers), Int64(quizManager.currentQuiz.count)))
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.9))
                        
                        if quizManager.hasPassed() {
                            Text("Daily streak completed!")
                                .font(.headline)
                                .foregroundColor(.green)
                                .padding()
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(10)
                            
                            // Show next review date from spaced repetition
                            nextReviewDateView
                            
                            continueButton
                        } else {
                            retryOrCloseSection
                        }
                    }
                    .padding()
                }
            }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .overlay {
            if showStreakCelebration {
                streakCelebrationOverlay
            }
        }
        .onAppear {
            print("QuizView appeared for word: \(word.word)")
            // Load quiz when view appears
            quizManager.loadAttemptsForToday()
            
            // Always reset and start a new quiz when view appears
            quizManager.currentQuestionIndex = 0
            quizManager.selectedAnswerIndex = nil
            quizManager.correctAnswers = 0
            quizManager.quizCompleted = false
            quizManager.currentQuiz = []
            showingAnswerFeedback = false
            currentAnswerWasCorrect = nil
            isAutoAdvancingAfterCorrect = false
            
            // Start quiz
            let success = quizManager.startQuiz(for: word)
            print("Quiz start result: \(success), Quiz count: \(quizManager.currentQuiz.count)")
            if success {
                AppAnalytics.shared.log(AppAnalyticsEventName.quizStarted, params: [
                    "quiz_mode": "daily",
                    "word_id": word.id.uuidString,
                    "question_count": String(quizManager.currentQuiz.count)
                ])
            }
            
            if !success || quizManager.currentQuiz.isEmpty {
                print("ERROR: Quiz failed to start. Word: \(word.word), Definition: \(word.definition)")
            }
        }
        .onChange(of: quizManager.quizCompleted) { completed in
            if completed {
                quizManager.saveAttemptsForToday()
                if !hasLoggedQuizCompletion {
                    AppAnalytics.shared.log(AppAnalyticsEventName.quizCompleted, params: [
                        "quiz_mode": "daily",
                        "word_id": word.id.uuidString,
                        "correct_count": String(quizManager.correctAnswers),
                        "question_count": String(quizManager.currentQuiz.count)
                    ])
                    hasLoggedQuizCompletion = true
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var streakCelebrationOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.celebrationFlameGradient)
                    .scaleEffect(streakScale)
                Text("Day completed!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text(String(format: String(localized: "%lld day streak"), Int64(streakManager.currentStreak)))
                    .font(.headline)
                    .foregroundColor(.orange)
            }
            .padding(32)
            .background(AppColors.Lavender)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                streakScale = 1.2
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    streakScale = 1.0
                }
            }
        }
    }
    
    private var nextReviewDateView: some View {
        let nextReview = progressManager.nextDueDate(for: word.id)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current

        return Text(String(format: String(localized: "Next review: %@"), formatter.string(from: nextReview)))
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.85))
            .padding(.top, 8)
    }

    private var quizProgressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let progress = quizProgressValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppColors.glassCardTitle.opacity(0.12))

                Capsule()
                    .fill(AppColors.quizProgressGradient)
                    .frame(width: max(8, width * progress))
            }
        }
        .frame(height: 8)
    }

    private var quizProgressValue: CGFloat {
        guard !quizManager.currentQuiz.isEmpty else { return 0 }
        var completedQuestions = quizManager.currentQuestionIndex
        if showingAnswerFeedback {
            completedQuestions += 1
        }
        let clamped = min(max(completedQuestions, 0), quizManager.currentQuiz.count)
        return CGFloat(clamped) / CGFloat(quizManager.currentQuiz.count)
    }
    
    private var continueButton: some View {
        Button(action: {
            // Update spaced repetition progress
            let correct = quizManager.getCorrectCount()
            let total = quizManager.getTotalQuestionsAsked()
            progressManager.updateProgress(for: word.id, correct: correct, total: total)
            
            // Record quiz stats
            statsManager.recordQuizCompletion(correct: correct, total: total)
            
            // Kelime bazlı + zaman verisi (ML için), Firestore: quizEvents
            quizEventManager.record(wordId: word.id, correct: correct, total: total, completedAt: Date())
            
            // Mark word as quizzed in diary
            diaryManager.markWordAsQuizzed(word, for: Date())
            
            // Mark streak as completed (only once per day); ilk quizde streak kutlaması göster
            let wasFirstQuizToday = !streakManager.isDayCompleted(Date())
            if wasFirstQuizToday {
                streakManager.markDayCompleted()
                showStreakCelebration = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    showStreakCelebration = false
                    dismiss()
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    dismiss()
                }
            }
        }) {
            Text("Continue")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.primaryButtonGradient)
                .cornerRadius(10)
        }
        .padding(.horizontal)
    }
    
    private var retryOrCloseSection: some View {
        Group {
            if canRetry && quizManager.quizAttemptsToday < 3 {
                Button(action: {
                    quizManager.resetQuiz()
                    _ = quizManager.startQuiz(for: word)
                }) {
                    Text("Retry Quiz")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.primaryButtonGradient)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            } else {
                Text("Maximum attempts reached for today")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.82))
            }
            
            Button(action: {
                dismiss()
            }) {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
    }

    private var nextButtonTitle: String {
        let isLastQuestion = quizManager.currentQuestionIndex >= max(0, quizManager.currentQuiz.count - 1)
        return isLastQuestion ? String(localized: "See Results") : String(localized: "Next Question")
    }

    private var buttonTitle: String {
        if isAutoAdvancingAfterCorrect && currentAnswerWasCorrect == true {
            return String(localized: "Correct")
        }
        return showingAnswerFeedback ? nextButtonTitle : String(localized: "Check Answer")
    }

    @ViewBuilder
    private func optionBackground(for index: Int, question: QuizQuestion) -> some View {
        if !showingAnswerFeedback {
            if quizManager.selectedAnswerIndex == index {
                AppColors.primaryButtonGradient.opacity(0.26)
            } else {
                Color.white.opacity(0.13)
            }
        } else if index == question.correctAnswerIndex {
            Color.green.opacity(0.26)
        } else if quizManager.selectedAnswerIndex == index {
            Color.red.opacity(0.22)
        } else {
            Color.white.opacity(0.13)
        }
    }

    private func feedbackCard(for question: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((currentAnswerWasCorrect ?? false) ? "Correct ✅" : "Not quite ❌")
                .font(.subheadline.weight(.semibold))
                .foregroundColor((currentAnswerWasCorrect ?? false) ? .green : .red)

            Text("Correct answer:")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.82))

            Text(question.options[question.correctAnswerIndex])
                .font(.subheadline)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
        }
    }

    private func commitFeedbackAndAdvance() {
        _ = quizManager.advanceAfterFeedback()
        showingAnswerFeedback = false
        currentAnswerWasCorrect = nil
        isAutoAdvancingAfterCorrect = false
        if quizManager.quizCompleted {
            showingResult = true
            canRetry = quizManager.canRetry()
        }
    }
}

// Need to fix the reference to wordManager
struct QuizView_Previews: PreviewProvider {
    static var previews: some View {
        QuizView(word: Word(word: "Test", definition: "A test definition", exampleSentence: "This is a test sentence"))
            .environmentObject(StreakManager())
            .environmentObject(DiaryManager())
            .environmentObject(StatsManager())
            .environmentObject(WordProgressManager())
            .environmentObject(QuizEventManager())
    }
}
