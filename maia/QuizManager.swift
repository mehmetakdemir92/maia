//
//  QuizManager.swift
//  maia
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
    private let questionsPerQuiz = 5
    private let requiredCorrectAnswers = 4 // Pass threshold for 5 questions

    private struct SeededGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func next() -> UInt64 {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2685821657736338717
        }

        mutating func int(upperBound: Int) -> Int {
            guard upperBound > 0 else { return 0 }
            return Int(next() % UInt64(upperBound))
        }

        mutating func shuffle<T>(_ array: inout [T]) {
            guard array.count > 1 else { return }
            for i in stride(from: array.count - 1, through: 1, by: -1) {
                let j = int(upperBound: i + 1)
                if i != j { array.swapAt(i, j) }
            }
        }
    }

    private func stableSeed(for text: String) -> UInt64 {
        // FNV-1a 64-bit
        var hash: UInt64 = 1469598103934665603
        for b in text.utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return hash
    }

    private func quizDayISO(for date: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Aynı takvim gününde farklı kelime quizlerinde aynı genel şablon cümlenin tekrarını azaltır.
    private func globalBlankSentencesKey(for dayISO: String) -> String {
        "quizGlobalBlankSentences_\(dayISO)"
    }

    private func loadGlobalUsedBlankSentences() -> Set<String> {
        let day = quizDayISO()
        let key = globalBlankSentencesKey(for: day)
        guard let arr = UserDefaults.standard.stringArray(forKey: key) else { return [] }
        return Set(arr)
    }

    private func registerGlobalBlankSentence(_ sentence: String) {
        let norm = normalized(sentence)
        guard !norm.isEmpty else { return }
        let day = quizDayISO()
        let key = globalBlankSentencesKey(for: day)
        var set = loadGlobalUsedBlankSentences()
        guard set.insert(norm).inserted else { return }
        UserDefaults.standard.set(Array(set), forKey: key)
    }

    /// Kelime + gün ile farklı başlangıç; ardından shuffle. Önce bugün hiç kullanılmayan şablonlar.
    private func orderedNonTargetTemplates(
        targetLemma: String,
        templates: [(sentence: String, answer: String)],
        rng: inout SeededGenerator
    ) -> [(sentence: String, answer: String)] {
        var pool = templates
        guard !pool.isEmpty else { return [] }
        let rot = Int(stableSeed(for: "\(targetLemma.lowercased())|\(quizDayISO())|ntrot") % UInt64(pool.count))
        if rot > 0 {
            pool = Array(pool[rot...] + pool[..<rot])
        }
        rng.shuffle(&pool)
        let globalUsed = loadGlobalUsedBlankSentences()
        let fresh = pool.filter { !globalUsed.contains(normalized($0.sentence)) }
        let reused = pool.filter { globalUsed.contains(normalized($0.sentence)) }
        return fresh + reused
    }

    private func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func makeOptions(correct: String, distractors: [String], count: Int = 4, rng: inout SeededGenerator) -> ([String], Int) {
        var unique: [String] = []
        var seen = Set<String>()

        func appendIfUnique(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let key = normalized(trimmed)
            guard !seen.contains(key) else { return }
            seen.insert(key)
            unique.append(trimmed)
        }

        appendIfUnique(correct)
        distractors.forEach(appendIfUnique)

        if unique.count < count {
            [
                "A formal legal document",
                "A type of machine component",
                "A weather-related phrase",
                "A specific measurement unit",
                "A historical title"
            ].forEach(appendIfUnique)
        }

        var selected = Array(unique.prefix(count))
        rng.shuffle(&selected)
        let correctIndex = selected.firstIndex(where: { normalized($0) == normalized(correct) }) ?? 0
        return (selected, correctIndex)
    }

    private func similarDefinition(for definition: String) -> String {
        let clean = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("to "), clean.count > 3 {
            let rest = String(clean.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return "To \(rest), usually in a clear everyday context."
        }
        return "It means: \(clean)"
    }

    /// Tanım şıkları için kelime sayısı (boşlukla ayrılmış tokenlar).
    private func definitionWordCount(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    /// İlk sözcük anahtarı — şıkların aynı harfle başlamasını / aynı ilk kelimeyi paylaşmasını engellemek için.
    private func definitionFirstWordKey(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).first else { return "" }
        return String(first)
            .trimmingCharacters(in: CharacterSet.punctuationCharacters)
            .lowercased()
    }

    /// Yanlış tanım havuzu: farklı cümle başları; uzunluklar çoğunlukla orta (doğru şıkla hizalanabilir).
    private func definitionWrongAnswerPool() -> [String] {
        [
            "It describes how people behave in everyday conversations.",
            "To express doubt before you make a final decision about something.",
            "The usual way teams record progress at work each week.",
            "This refers to a short label we give to a complex idea.",
            "People use this when they want to soften critical feedback politely.",
            "When something repeats often, we say it happens on a regular basis.",
            "You might hear this in news stories about slow policy changes.",
            "Many textbooks introduce the idea with a simple diagram first.",
            "Learning this helps readers follow longer arguments in essays.",
            "Writers choose this word to sound more precise than common synonyms.",
            "During meetings, speakers use this to signal polite agreement quickly.",
            "Instead of guessing, listeners ask for one concrete real example.",
            "Without context, fluent speakers may still misunderstand the nuance.",
            "Often the term appears in headlines rather than in full articles.",
            "Sometimes teachers use this to check informal understanding only.",
            "One common mistake is to confuse it with a near synonym nearby.",
            "Readers notice it when the tone shifts from formal to casual speech.",
            "Speakers rely on it to connect two related ideas in one sentence.",
            "Courses often pair this concept with practice dialogues and drills.",
            "Editors remove it when a simpler phrase would communicate the same point.",
            "Listeners infer it from stress patterns and surrounding vocabulary choices.",
            "Students remember it more easily when they see it inside a short story.",
            "Podcasts repeat it slowly so beginners can catch the exact usage.",
            "Reviewers praise books that explain it without unnecessary jargon.",
            "Translators struggle when the target language lacks a direct equivalent.",
            "Native speakers rarely define it because everyone picks it up early.",
            "Grammar guides list it next to related patterns you should compare.",
            "Fluent use of it signals that you can handle abstract topics well."
        ]
    }

    /// Doğru tanım + 3 yanlış: ilk kelimeler farklı, kelime sayıları yakın (gevşetilerek doldurulur).
    private func makeDefinitionQuestion(for word: Word, rng: inout SeededGenerator) -> QuizQuestion {
        let correctDefinition = similarDefinition(for: word.definition)
        let correctKey = definitionFirstWordKey(correctDefinition)
        let targetWC = definitionWordCount(correctDefinition)

        var pool = definitionWrongAnswerPool()
        rng.shuffle(&pool)

        func pickWrongs(maxWordDiff: Int) -> [String] {
            var chosen: [String] = []
            var usedFirst: Set<String> = [correctKey]
            for c in pool {
                guard chosen.count < 3 else { break }
                if normalized(c) == normalized(correctDefinition) { continue }
                let fw = definitionFirstWordKey(c)
                guard !fw.isEmpty else { continue }
                if usedFirst.contains(fw) { continue }
                if abs(definitionWordCount(c) - targetWC) > maxWordDiff { continue }
                usedFirst.insert(fw)
                chosen.append(c)
            }
            return chosen
        }

        var band = max(2, min(5, targetWC / 4))
        var wrongs = pickWrongs(maxWordDiff: band)
        if wrongs.count < 3 { wrongs = pickWrongs(maxWordDiff: band + 3) }
        if wrongs.count < 3 { wrongs = pickWrongs(maxWordDiff: band + 8) }
        if wrongs.count < 3 { wrongs = pickWrongs(maxWordDiff: 999) }

        // Hâlâ eksikse: ilk kelime kuralını gevşet (kelime sayısına yakın kalanlar).
        if wrongs.count < 3 {
            var usedFirst: Set<String> = [correctKey]
            wrongs.forEach { usedFirst.insert(definitionFirstWordKey($0)) }
            for c in pool where wrongs.count < 3 {
                if wrongs.contains(where: { normalized($0) == normalized(c) }) { continue }
                if abs(definitionWordCount(c) - targetWC) > band + 5 { continue }
                let fw = definitionFirstWordKey(c)
                if usedFirst.contains(fw) { continue }
                usedFirst.insert(fw)
                wrongs.append(c)
            }
        }
        if wrongs.count < 3 {
            var usedFirst: Set<String> = [correctKey]
            wrongs.forEach { usedFirst.insert(definitionFirstWordKey($0)) }
            for c in pool where wrongs.count < 3 {
                if normalized(c) == normalized(correctDefinition) { continue }
                if wrongs.contains(where: { normalized($0) == normalized(c) }) { continue }
                let fw = definitionFirstWordKey(c)
                if usedFirst.contains(fw) { continue }
                usedFirst.insert(fw)
                wrongs.append(c)
            }
        }

        let wrongsThree = Array(wrongs.prefix(3))
        var options = [correctDefinition] + wrongsThree
        var padIndex = 0
        let pads = [
            "One everyday use appears in polite requests and short replies.",
            "Courses often drill this with listen-and-repeat exercises only.",
            "Readers meet it first in graded texts before newspapers use it."
        ]
        var safety = 0
        while options.count < 4, safety < 20 {
            safety += 1
            let p = pads[padIndex % pads.count]
            padIndex += 1
            if options.contains(where: { normalized($0) == normalized(p) }) { continue }
            if definitionFirstWordKey(p) == correctKey { continue }
            options.append(p)
        }
        while options.count < 4 {
            options.append("Fluent speakers use it without stopping to define it first.")
        }
        options = Array(options.prefix(4))
        rng.shuffle(&options)
        let correctIndex = options.firstIndex(where: { normalized($0) == normalized(correctDefinition) }) ?? 0

        return QuizQuestion(
            question: String(format: String(localized: "What does \"%@\" mean?"), word.word),
            options: options,
            correctAnswerIndex: correctIndex
        )
    }

    private func blankDistractorPool(for word: Word, rng: inout SeededGenerator) -> [String] {
        var pool: [String]
        switch word.partOfSpeech?.lowercased() {
        case "verb":
            pool = ["choose", "notice", "explain", "compare", "avoid", "accept", "refuse", "mention", "imply"]
        case "noun":
            pool = ["reason", "method", "result", "issue", "habit", "detail", "topic", "risk", "context"]
        case "adj", "adjective":
            pool = ["clear", "brief", "likely", "recent", "formal", "typical", "obvious", "subtle"]
        case "adv", "adverb":
            pool = ["quickly", "rarely", "partly", "fully", "nearly", "hardly", "widely"]
        default:
            pool = ["improve", "reduce", "arrange", "observe", "remove", "prepare", "confirm", "support"]
        }
        rng.shuffle(&pool)
        return pool
    }

    private func makeBlankOptions(correct: String, targetWord: String, word: Word, rng: inout SeededGenerator) -> ([String], Int) {
        let genericDistractors = blankDistractorPool(for: word, rng: &rng)
        var distractorPool = [targetWord] + genericDistractors
        rng.shuffle(&distractorPool)
        let (rawOptions, rawCorrectIndex) = makeOptions(
            correct: correct,
            distractors: distractorPool,
            rng: &rng
        )

        var options = rawOptions
        var correctIndex = rawCorrectIndex
        let containsTarget = options.contains { normalized($0) == normalized(targetWord) }
        if !containsTarget {
            let replaceIndex = options.indices.first { $0 != correctIndex } ?? 0
            options[replaceIndex] = targetWord
            if normalized(correct) == normalized(targetWord) {
                correctIndex = replaceIndex
            }
        }

        return (options, correctIndex)
    }

    /// Kelimenin örnek cümlelerinden (definition tarafından üretilmiş) boşluk doldurma üretir.
    private func exampleSentences(from word: Word) -> [String] {
        [word.exampleSentence, word.exampleSentence2, word.exampleSentence3]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// İlk eşleşen tokenu (kelime sınırı, büyük/küçük harf duyarsız) `_____` ile değiştirir.
    private func blankFillFromExample(sentence: String, lemma: String, pickOccurrence: Int) -> (sentence: String, answer: String)? {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !lemma.isEmpty else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: lemma)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else { return nil }
        let ns = trimmed as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: trimmed, options: [], range: fullRange)
        guard !matches.isEmpty else { return nil }
        let idx = pickOccurrence % matches.count
        let r = matches[idx].range
        guard let range = Range(r, in: trimmed) else { return nil }
        let actual = String(trimmed[range])
        var out = trimmed
        out.replaceSubrange(range, with: "_____")
        return (out, actual)
    }

    private func makeBlankQuestions(for word: Word, count: Int, rng: inout SeededGenerator) -> [QuizQuestion] {
        var nonTargetTemplates: [(sentence: String, answer: String)] = []

        let target = word.word.trimmingCharacters(in: .whitespacesAndNewlines)

        var fromExamples: [(sentence: String, answer: String)] = []
        for sentence in exampleSentences(from: word) {
            let pick = rng.int(upperBound: 10_000)
            if let pair = blankFillFromExample(sentence: sentence, lemma: target, pickOccurrence: pick) {
                fromExamples.append(pair)
            }
        }
        rng.shuffle(&fromExamples)

        // Doğru cevap hedef kelime olmayan şablonlar
        nonTargetTemplates.append(contentsOf: [
            (sentence: "Please _____ to the latest report before the meeting.", answer: "refer"),
            (sentence: "We need to _____ this issue before tomorrow's deadline.", answer: "address"),
            (sentence: "The team decided to _____ the event because of heavy rain.", answer: "postpone"),
            (sentence: "Please _____ your answer with one clear reason.", answer: "support"),
            (sentence: "You can _____ this file in the shared folder.", answer: "save"),
            (sentence: "They will _____ the final results next Monday.", answer: "announce"),
            (sentence: "I usually _____ a short plan before I start work.", answer: "prepare"),
            (sentence: "Could you _____ this box near the window?", answer: "move"),
            (sentence: "The teacher asked us to _____ our ideas in one paragraph.", answer: "summarize"),
            (sentence: "Before launching, engineers must _____ the system carefully.", answer: "test"),
            (sentence: "The manager will _____ the proposal after lunch.", answer: "review"),
            (sentence: "To avoid mistakes, always _____ the instructions twice.", answer: "read"),
            (sentence: "We should _____ our budget before hiring new staff.", answer: "adjust"),
            (sentence: "Please _____ your name at the top of the page.", answer: "write"),
            (sentence: "The team needs to _____ customer feedback every week.", answer: "collect"),
            (sentence: "Could you _____ the lights before leaving the room?", answer: "turn off"),
            (sentence: "The editor will _____ the article for clarity.", answer: "edit"),
            (sentence: "They had to _____ the route because of roadwork.", answer: "change"),
            (sentence: "You must _____ your passport at the airport desk.", answer: "show"),
            (sentence: "Our group will _____ the project on Friday morning.", answer: "present"),
            (sentence: "Please _____ the form and return it by email.", answer: "complete"),
            (sentence: "The doctor advised him to _____ more water daily.", answer: "drink"),
            (sentence: "We should _____ the data before making a decision.", answer: "analyze"),
            (sentence: "The company plans to _____ into new markets next year.", answer: "expand"),
            (sentence: "Can you _____ this message to the whole class?", answer: "forward"),
            (sentence: "He tried to _____ calm during the interview.", answer: "stay"),
            (sentence: "The app will _____ users when a task is overdue.", answer: "notify"),
            (sentence: "She needed time to _____ her thoughts before speaking.", answer: "organize"),
            (sentence: "The hotel staff will _____ your bags to your room.", answer: "carry"),
            (sentence: "We should _____ the meeting if too few people can attend.", answer: "cancel"),
            (sentence: "The lawyer will _____ the contract for hidden fees.", answer: "check"),
            (sentence: "Try not to _____ your colleagues during the presentation.", answer: "interrupt"),
            (sentence: "The city plans to _____ a new bike lane next spring.", answer: "build"),
            (sentence: "Please _____ quietly so you do not wake the baby.", answer: "speak"),
            (sentence: "The software can _____ large files in the background.", answer: "download"),
            (sentence: "We hope to _____ our costs without lowering quality.", answer: "reduce"),
            (sentence: "The guide will _____ us through the museum in one hour.", answer: "lead"),
            (sentence: "You should _____ your password if you suspect a leak.", answer: "change"),
            (sentence: "The storm may _____ flights until tomorrow morning.", answer: "delay"),
            (sentence: "Please _____ your seatbelt before we take off.", answer: "fasten"),
            (sentence: "The report fails to _____ the main risk clearly.", answer: "explain")
        ])

        var questions: [QuizQuestion] = []
        var usedSentences = Set<String>()
        var usedAnswers = Set<String>()
        var prompts = [
            String(localized: "Fill in the blank:"),
            String(localized: "Choose the best word to complete:"),
            String(localized: "Complete the sentence:"),
            String(localized: "Pick the most natural word:")
        ]
        rng.shuffle(&prompts)
        var promptIndex = 0
        let orderedNonTargets = orderedNonTargetTemplates(targetLemma: target, templates: nonTargetTemplates, rng: &rng)

        // Önce örnek cümlelerden (hedef kelime doğru cevap); kalanı genel şablonlar.
        let maxTargetBlanks = min(2, fromExamples.count, count)
        let targetItems = Array(fromExamples.prefix(maxTargetBlanks))

        func appendQuestion(_ item: (sentence: String, answer: String)) {
            guard questions.count < count else { return }
            let key = normalized(item.sentence)
            guard !usedSentences.contains(key) else { return }
            let answerKey = normalized(item.answer)
            guard !usedAnswers.contains(answerKey) else { return }
            usedSentences.insert(key)
            usedAnswers.insert(answerKey)

            let (options, correctIndex) = makeBlankOptions(
                correct: item.answer,
                targetWord: target,
                word: word,
                rng: &rng
            )
            let prompt = prompts[promptIndex % prompts.count]
            promptIndex += 1
            questions.append(
                QuizQuestion(
                    question: "\(prompt) \(item.sentence)",
                    options: options,
                    correctAnswerIndex: correctIndex
                )
            )
            // Sadece genel şablonları işaretle; günlük kelime örnek cümleleri kelimeye özel.
            if normalized(item.answer) != normalized(target) {
                registerGlobalBlankSentence(item.sentence)
            }
        }

        for item in targetItems {
            appendQuestion(item)
        }
        for item in orderedNonTargets {
            guard questions.count < count else { break }
            appendQuestion(item)
        }

        // Eksik kalırsa: kalan örnek cümleler + genel şablonlar.
        if questions.count < count {
            var fallbackPool = Array(fromExamples.dropFirst(maxTargetBlanks)) + orderedNonTargets
            rng.shuffle(&fallbackPool)
            for item in fallbackPool {
                if questions.count >= count { break }
                appendQuestion(item)
            }
        }

        // Soru sırasını karıştır (deterministic)
        rng.shuffle(&questions)

        return questions
    }
    
    func generateQuiz(for word: Word, count: Int = 5, attemptNumber: Int = 0) -> [QuizQuestion] {
        let seedInput = "\(word.word.lowercased())|\(quizDayISO())|\(count)|a\(attemptNumber)"
        var rng = SeededGenerator(seed: stableSeed(for: seedInput))
        let desiredCount = max(1, count)
        var questions: [QuizQuestion] = [makeDefinitionQuestion(for: word, rng: &rng)]
        let blankQuestions = makeBlankQuestions(for: word, count: max(0, desiredCount - 1), rng: &rng)
        questions.append(contentsOf: blankQuestions)
        return Array(questions.prefix(desiredCount))
    }
    
    func startQuiz(for word: Word) -> Bool {
        print("Starting quiz for word: \(word.word)")
        quizAttemptsToday += 1
        saveAttemptsForToday()

        // Generate 5 questions (attemptNumber: aynı gün tekrar denemede farklı boşluk / sıra)
        let quiz = generateQuiz(for: word, count: questionsPerQuiz, attemptNumber: quizAttemptsToday)
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

    /// Returns correctness for the currently selected answer without advancing.
    func isCurrentSelectionCorrect() -> Bool? {
        guard let selectedIndex = selectedAnswerIndex,
              currentQuestionIndex < currentQuiz.count else { return nil }
        return selectedIndex == currentQuiz[currentQuestionIndex].correctAnswerIndex
    }

    /// Commits selected answer, updates score and advances to next question.
    /// - Returns: true if quiz is completed after advancing.
    func advanceAfterFeedback() -> Bool {
        guard let isCorrect = isCurrentSelectionCorrect() else { return false }

        if isCorrect {
            correctAnswers += 1
        }

        if currentQuestionIndex < currentQuiz.count - 1 {
            currentQuestionIndex += 1
            selectedAnswerIndex = nil
            return false
        } else {
            quizCompleted = true
            return true
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
        // Pass threshold: 4+ correct out of 5
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
