//
//  QuizManager.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import Foundation
import Combine

struct QuizQuestion {
    let question: String
    let options: [String]
    let correctAnswerIndex: Int
}

class QuizManager: ObservableObject {
    @Published var currentQuiz: [QuizQuestion] = []
    @Published var currentQuestionIndex: Int = 0
    @Published var selectedAnswerIndex: Int? = nil
    @Published var correctAnswers: Int = 0
    @Published var quizCompleted: Bool = false
    @Published var quizAttemptsToday: Int = 0
    
    private let maxAttemptsPerDay = 3
    private let questionsPerQuiz = 10 // Always 10 questions
    private let requiredCorrectAnswers = 7 // Pass threshold for 10 questions
    
    func generateQuiz(for word: Word, count: Int = 10) -> [QuizQuestion] {
        var questions: [QuizQuestion] = []
        
        // Question types pool
        let questionTypes: [(Word) -> QuizQuestion] = [
            // Type 1: Definition question
            { word in
                let wrongDefinitions = [
                    "A type of flower or plant",
                    "A musical instrument or sound",
                    "A cooking technique or method",
                    "A historical event or period",
                    "A geographical location",
                    "A scientific term or concept",
                    "A type of animal or creature",
                    "A color or visual quality"
                ].shuffled()
                let correctDefIndex = Int.random(in: 0...3)
                var defOptions = Array(wrongDefinitions.prefix(3))
                defOptions.insert(word.definition, at: correctDefIndex)
                return QuizQuestion(
                    question: "What is the definition of \"\(word.word)\"?",
                    options: defOptions,
                    correctAnswerIndex: correctDefIndex
                )
            },
            // Type 2: Sentence usage question
            { word in
                let wrongSentences = [
                    "The \(word.word.lowercased()) was very delicious and tasty.",
                    "I \(word.word.lowercased())ed to the store yesterday morning.",
                    "The \(word.word.lowercased()) is a beautiful color in the rainbow.",
                    "She \(word.word.lowercased())ed her homework quickly and efficiently.",
                    "We saw a \(word.word.lowercased()) flying in the sky.",
                    "The \(word.word.lowercased()) made a loud noise when it rang."
                ].shuffled()
                let correctSentIndex = Int.random(in: 0...3)
                var sentOptions = Array(wrongSentences.prefix(3))
                sentOptions.insert(word.exampleSentence, at: correctSentIndex)
                return QuizQuestion(
                    question: "Which sentence uses \"\(word.word)\" correctly?",
                    options: sentOptions,
                    correctAnswerIndex: correctSentIndex
                )
            },
            // Type 3: Fill in the blank
            { word in
                var sentenceWithBlank = word.exampleSentence
                if let range = sentenceWithBlank.range(of: word.word, options: .caseInsensitive) {
                    sentenceWithBlank = sentenceWithBlank.replacingCharacters(in: range, with: "_____")
                } else {
                    let words = sentenceWithBlank.components(separatedBy: " ")
                    if !words.isEmpty {
                        sentenceWithBlank = sentenceWithBlank.replacingOccurrences(of: words[0], with: "_____")
                    }
                }
                let wrongWords = [
                    word.word.capitalized,
                    word.word.uppercased(),
                    "similar",
                    "different"
                ].shuffled()
                let correctBlankIndex = Int.random(in: 0...3)
                var blankOpts = Array(wrongWords.prefix(3))
                blankOpts.insert(word.word, at: correctBlankIndex)
                return QuizQuestion(
                    question: "Fill in the blank: \(sentenceWithBlank)",
                    options: blankOpts,
                    correctAnswerIndex: correctBlankIndex
                )
            },
            // Type 4: Synonym/Antonym (variation)
            { word in
                let wrongOptions = [
                    "Opposite meaning",
                    "Unrelated concept",
                    "Different context",
                    "Similar but incorrect"
                ].shuffled()
                let correctIndex = Int.random(in: 0...3)
                var options = Array(wrongOptions.prefix(3))
                options.insert(word.definition, at: correctIndex)
                return QuizQuestion(
                    question: "What best describes \"\(word.word)\"?",
                    options: options,
                    correctAnswerIndex: correctIndex
                )
            },
            // Type 5: Context question
            { word in
                let contexts = [
                    "Formal writing",
                    "Casual conversation",
                    "Academic paper",
                    "Business meeting"
                ].shuffled()
                let correctIndex = Int.random(in: 0...3)
                var options = Array(contexts.prefix(3))
                options.insert("All of the above", at: correctIndex)
                return QuizQuestion(
                    question: "In which context would you use \"\(word.word)\"?",
                    options: options,
                    correctAnswerIndex: correctIndex
                )
            }
        ]
        
        // Generate requested number of questions, cycling through types
        for i in 0..<count {
            let typeIndex = i % questionTypes.count
            let question = questionTypes[typeIndex](word)
            questions.append(question)
        }
        
        return questions
    }
    
    func startQuiz(for word: Word) -> Bool {
        print("Starting quiz for word: \(word.word)")
        quizAttemptsToday += 1
        saveAttemptsForToday()
        
        // Generate 10 questions
        let quiz = generateQuiz(for: word, count: questionsPerQuiz)
        print("Generated quiz with \(quiz.count) questions")
        
        currentQuiz = quiz
        currentQuestionIndex = 0
        selectedAnswerIndex = nil
        correctAnswers = 0
        quizCompleted = false
        
        if currentQuiz.isEmpty {
            print("ERROR: Quiz generation failed for word: \(word.word)")
            return false
        }
        
        print("Quiz started successfully with \(currentQuiz.count) questions")
        return true
    }
    
    func submitAnswer() -> Bool {
        guard let selectedIndex = selectedAnswerIndex else { return false }
        
        let isCorrect = selectedIndex == currentQuiz[currentQuestionIndex].correctAnswerIndex
        
        if isCorrect {
            correctAnswers += 1
        }
        
        if currentQuestionIndex < currentQuiz.count - 1 {
            currentQuestionIndex += 1
            selectedAnswerIndex = nil
            return false // Quiz not completed
        } else {
            quizCompleted = true
            return true // Quiz completed
        }
    }
    
    func canRetry() -> Bool {
        return quizAttemptsToday < maxAttemptsPerDay && correctAnswers < requiredCorrectAnswers
    }
    
    func selectAnswer(_ index: Int) {
        selectedAnswerIndex = index
    }
    
    /// Get total questions asked (for spaced repetition)
    func getTotalQuestionsAsked() -> Int {
        return currentQuiz.count
    }
    
    /// Get correct count (for spaced repetition)
    func getCorrectCount() -> Int {
        return correctAnswers
    }
    
    func resetQuiz() {
        currentQuiz = []
        currentQuestionIndex = 0
        selectedAnswerIndex = nil
        correctAnswers = 0
        quizCompleted = false
        saveAttemptsForToday()
    }
    
    func hasPassed() -> Bool {
        // Pass threshold: 7+ correct out of 10
        return correctAnswers >= requiredCorrectAnswers
    }
    
    func loadAttemptsForToday() {
        let today = getDateString(Date())
        quizAttemptsToday = UserDefaults.standard.integer(forKey: "quizAttempts_\(today)")
    }
    
    func saveAttemptsForToday() {
        let today = getDateString(Date())
        UserDefaults.standard.set(quizAttemptsToday, forKey: "quizAttempts_\(today)")
    }
    
    private func getDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
