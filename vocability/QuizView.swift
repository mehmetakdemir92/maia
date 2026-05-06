//
//  QuizView.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct QuizView: View {
    let word: Word
    @EnvironmentObject var streakManager: StreakManager
    @EnvironmentObject var diaryManager: DiaryManager
    @StateObject private var quizManager = QuizManager()
    @StateObject private var progressManager = WordProgressManager()
    @Environment(\.dismiss) var dismiss
    @State private var showingResult = false
    @State private var canRetry = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !quizManager.quizCompleted {
                    // Quiz in progress
                    VStack(spacing: 20) {
                        // Progress indicator
                        HStack {
                            Text("Question \(quizManager.currentQuestionIndex + 1) of \(quizManager.currentQuiz.count)")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Correct: \(quizManager.correctAnswers)")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal)
                        
                        ProgressView(value: Double(quizManager.currentQuestionIndex), total: Double(quizManager.currentQuiz.count))
                            .padding(.horizontal)
                        
                        if !quizManager.currentQuiz.isEmpty && quizManager.currentQuestionIndex < quizManager.currentQuiz.count {
                            let question = quizManager.currentQuiz[quizManager.currentQuestionIndex]
                            
                            // Question
                            Text(question.question)
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                                .padding()
                                .frame(maxWidth: .infinity)
                            
                            // Answer options
                            VStack(spacing: 12) {
                                ForEach(0..<question.options.count, id: \.self) { index in
                                    Button(action: {
                                        quizManager.selectAnswer(index)
                                    }) {
                                        HStack {
                                            Text(question.options[index])
                                                .font(.body)
                                                .foregroundColor(.primary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            if quizManager.selectedAnswerIndex == index {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(AppColors.primaryButton)
                                            }
                                        }
                                        .padding()
                                        .background(quizManager.selectedAnswerIndex == index ? AppColors.primaryButton.opacity(0.1) : Color(.systemGray6))
                                        .cornerRadius(10)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                            // Submit button
                            Button(action: {
                                _ = quizManager.submitAnswer()
                                if quizManager.quizCompleted {
                                    showingResult = true
                                    canRetry = quizManager.canRetry()
                                }
                            }) {
                                Text("Submit Answer")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(quizManager.selectedAnswerIndex != nil ? AppColors.primaryButton : Color.gray)
                                    .cornerRadius(10)
                            }
                            .disabled(quizManager.selectedAnswerIndex == nil)
                            .padding(.horizontal)
                        } else {
                            VStack(spacing: 16) {
                                ProgressView("Loading quiz...")
                                Text("Generating questions...")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }
                } else {
                    // Quiz completed - show results
                    VStack(spacing: 24) {
                        Text(quizManager.hasPassed() ? "🎉 Great Job!" : "Try Again")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("You got \(quizManager.correctAnswers) out of \(quizManager.currentQuiz.count) correct")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
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
        .navigationTitle("Quiz: \(word.word)")
        .navigationBarTitleDisplayMode(.large)
        .padding()
        .background(AppColors.background)
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
            
            // Start quiz
            let success = quizManager.startQuiz(for: word)
            print("Quiz start result: \(success), Quiz count: \(quizManager.currentQuiz.count)")
            
            if !success || quizManager.currentQuiz.isEmpty {
                print("ERROR: Quiz failed to start. Word: \(word.word), Definition: \(word.definition)")
            }
        }
        .onChange(of: quizManager.quizCompleted) { completed in
            if completed {
                quizManager.saveAttemptsForToday()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var nextReviewDateView: some View {
        let nextReview = progressManager.nextDueDate(for: word.id)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        return Text("Next review: \(formatter.string(from: nextReview))")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .padding(.top, 8)
    }
    
    private var continueButton: some View {
        Button(action: {
            // Update spaced repetition progress
            let correct = quizManager.getCorrectCount()
            let total = quizManager.getTotalQuestionsAsked()
            progressManager.updateProgress(for: word.id, correct: correct, total: total)
            
            // Mark word as quizzed in diary
            diaryManager.markWordAsQuizzed(word, for: Date())
            
            // Mark streak as completed (only once per day)
            if !streakManager.isDayCompleted(Date()) {
                streakManager.markDayCompleted()
            }
            
            // Small delay to ensure diary is updated before dismissing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                dismiss()
            }
        }) {
            Text("Continue")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.primaryButton)
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
                        .background(AppColors.primaryButton)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            } else {
                Text("Maximum attempts reached for today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
}

// Need to fix the reference to wordManager
struct QuizView_Previews: PreviewProvider {
    static var previews: some View {
        QuizView(word: Word(word: "Test", definition: "A test definition", exampleSentence: "This is a test sentence"))
            .environmentObject(StreakManager())
    }
}
