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
    private let questionsPerQuiz = 3
    /// Passing score: 2/3 correct (≈67%). Questions are curated, so
    /// a 100% bar is too harsh when one fill-in-the-blank may be misleading.
    private let requiredCorrectAnswers = 2

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

    /// Reduces reuse of the same generic template across different word quizzes on one calendar day.
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

    /// Deterministic start from word + day, then shuffle; prefer templates unused today.
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

    /// Masks the target word (and stem variants) in the definition with `it`;
    /// strips leading a/an/the articles — otherwise "an it"
    /// fragments remain. Ensures the correct choice does not contain the target word.
    private func maskTargetInDefinition(_ definition: String, target: String) -> String {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTarget.count >= 3 else { return definition }

        let stemLength: Int
        if trimmedTarget.count >= 6 {
            stemLength = trimmedTarget.count - 2
        } else if trimmedTarget.count >= 5 {
            stemLength = trimmedTarget.count - 1
        } else {
            stemLength = trimmedTarget.count
        }
        let stem = String(trimmedTarget.prefix(stemLength))
        let escapedStem = NSRegularExpression.escapedPattern(for: stem)
        let pattern = "(?:\\b(?:a|an|the|to)\\s+)?\\b\(escapedStem)[A-Za-z\\-']*\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return definition
        }
        let mutable = NSMutableString(string: definition)
        let range = NSRange(location: 0, length: mutable.length)
        regex.replaceMatches(in: mutable, options: [], range: range, withTemplate: "it")
        return (mutable as String)
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the correct answer without trimming the definition; only trailing punctuation is removed
    /// and the first letter is capitalized.
    /// Distractor length is adjusted to within ±1 word count of the correct answer.
    private func cleanedDefinitionAnswer(for rawDefinition: String) -> String {
        var clean = rawDefinition.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = clean.last, ".,;:!? ".contains(last) {
            clean.removeLast()
        }
        if clean.isEmpty {
            return "A common English usage learned in practice."
        }
        if let first = clean.first {
            clean = first.uppercased() + clean.dropFirst()
        }
        return clean + "."
    }

    /// Adjusts a distractor candidate to ±1 word count of the correct answer.
    /// - Returns as-is if already in range (trailing period normalized).
    /// - Pads shorter candidates with neutral filler to (target-1) words.
    /// - Discards candidates longer than target+1.
    private func definitionWrongCandidate(from raw: String, targetCount: Int) -> String? {
        var stripped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = stripped.last, ".,;:!? ".contains(last) {
            stripped.removeLast()
        }
        let count = stripped.split { $0.isWhitespace || $0.isNewline }.count
        guard count > 0 else { return nil }
        if abs(count - targetCount) <= 1 {
            return stripped + "."
        }
        if count > targetCount + 1 {
            return nil
        }
        let needed = (targetCount - 1) - count
        let fillers: [Int: String] = [
            1: "commonly",
            2: "in conversation",
            3: "in everyday speech",
            4: "in most everyday situations",
            5: "across many everyday conversations and situations",
            6: "during normal conversation in daily life situations",
            7: "during normal conversation in everyday daily life situations"
        ]
        guard let filler = fillers[needed] else { return nil }
        return stripped + " " + filler + "."
    }

    /// Word count for definition choices (space-separated tokens).
    private func definitionWordCount(_ s: String) -> Int {
        s.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
    }

    /// First-word key — prevents choices sharing the same leading letter or first word.
    private func definitionFirstWordKey(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).first else { return "" }
        return String(first)
            .trimmingCharacters(in: CharacterSet.punctuationCharacters)
            .lowercased()
    }

    /// Distractor pool: 6–7 words each; each line uses a different opening word and
    /// avoids formulaic cues like "It means:" or "To X, usually...".
    private func definitionWrongAnswerPool() -> [String] {
        [
            "A short note shared between coworkers.",
            "An informal phrase used among close friends.",
            "The polite way to greet new neighbors.",
            "Some general advice given without firm evidence.",
            "Strong evidence shown during a public debate.",
            "Detailed notes prepared before an important interview.",
            "Bright lights placed above busy city streets.",
            "Quiet practice done before a public speech.",
            "Heavy traffic seen during long holiday weekends.",
            "Brief feedback shared after a short meeting.",
            "Common errors made by beginners during exams.",
            "Loud announcements made at large train stations.",
            "Useful summaries added at article endings.",
            "Polite remarks exchanged between colleagues at work.",
            "Difficult questions raised during a final review.",
            "Helpful tips found in popular travel guides.",
            "Sharp criticism aimed at outdated business practices.",
            "Simple gestures used to welcome new visitors.",
            "Routine checks performed by airport security teams.",
            "Light reading enjoyed during long train trips.",
            "Old photographs displayed in small village museums.",
            "Short silence kept before official public speeches.",
            "Open discussions held among trusted senior colleagues.",
            "Sudden changes seen in busy financial markets.",
            "Public messages shared by official government bodies.",
            "Practical guidance offered to first-time student visitors.",
            "Friendly remarks added to a technical email.",
            "Strict deadlines enforced by demanding senior managers.",
            "Quick reminders sent before important client meetings.",
            "Careful planning done before a long trip.",
            "Modest praise offered by quiet team leaders.",
            "Tense moments shared during a final interview.",
            "Empty rooms left after the office closed.",
            "Random questions asked by curious young children.",
            "Slow gestures used by skilled stage performers."
        ]
    }

    /// Correct definition plus three distractors.
    /// - Correct answer: full word.definition (target word masked only).
    /// - Distractors: word count within ±1 of correct. Use pool match when available;
    ///   pad shorter ones; discard longer ones.
    private func makeDefinitionQuestion(for word: Word, rng: inout SeededGenerator) -> QuizQuestion {
        let masked = maskTargetInDefinition(word.definition, target: word.word)
        let correctDefinition = cleanedDefinitionAnswer(for: masked)
        let correctCount = definitionWordCount(correctDefinition)
        let correctKey = definitionFirstWordKey(correctDefinition)

        var pool = definitionWrongAnswerPool()
        rng.shuffle(&pool)

        func pickWrongs(allowSameFirstWord: Bool) -> [String] {
            var chosen: [String] = []
            var usedFirst: Set<String> = [correctKey]
            for raw in pool {
                guard chosen.count < 3 else { break }
                guard let c = definitionWrongCandidate(from: raw, targetCount: correctCount) else { continue }
                if normalized(c) == normalized(correctDefinition) { continue }
                let fw = definitionFirstWordKey(c)
                guard !fw.isEmpty else { continue }
                if !allowSameFirstWord, usedFirst.contains(fw) { continue }
                usedFirst.insert(fw)
                chosen.append(c)
            }
            return chosen
        }

        var wrongs = pickWrongs(allowSameFirstWord: false)
        if wrongs.count < 3 {
            // Relax first-word rule if pool is narrow; keep ±1 length rule.
            wrongs = pickWrongs(allowSameFirstWord: true)
        }

        var options = [correctDefinition] + Array(wrongs.prefix(3))

        // Neutral padding when pool is exhausted.
        let neutralBases = [
            "Used widely across everyday situations between speakers",
            "Often heard during friendly chats between coworkers",
            "Met regularly by learners reading short news articles",
            "Reached for quickly during simple polite daily conversations",
            "Found in textbooks at the start of beginner chapters"
        ]
        var padIndex = 0
        var safety = 0
        while options.count < 4, safety < 30 {
            safety += 1
            let raw = neutralBases[padIndex % neutralBases.count]
            padIndex += 1
            guard let p = definitionWrongCandidate(from: raw, targetCount: correctCount) else { continue }
            if options.contains(where: { normalized($0) == normalized(p) }) { continue }
            if definitionFirstWordKey(p) == correctKey { continue }
            options.append(p)
        }
        while options.count < 4 {
            options.append("Many learners pick this up over time.")
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

    /// Builds a fill-in-the-blank question from the word's example sentences.
    private func exampleSentences(from word: Word) -> [String] {
        [word.exampleSentence, word.exampleSentence2, word.exampleSentence3]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Replaces the first matching token (word boundary, case-insensitive) with `_____`.
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

        // Templates where the correct answer is not the target word
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

        // Prefer example sentences first; fill remainder with generic templates.
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
            // Mark only generic templates used; daily word examples are word-specific.
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

        // Fill gaps with remaining examples + generic templates.
        if questions.count < count {
            var fallbackPool = Array(fromExamples.dropFirst(maxTargetBlanks)) + orderedNonTargets
            rng.shuffle(&fallbackPool)
            for item in fallbackPool {
                if questions.count >= count { break }
                appendQuestion(item)
            }
        }

        // Shuffle question order (deterministic)
        rng.shuffle(&questions)

        return questions
    }
    
    func generateQuiz(for word: Word, count: Int = 3, attemptNumber: Int = 0) -> [QuizQuestion] {
        let desiredCount = max(1, count)
        if let curated = curatedQuestions(for: word, count: desiredCount, attemptNumber: attemptNumber),
           !curated.isEmpty {
            return curated
        }
        let seedInput = "\(word.word.lowercased())|\(quizDayISO())|\(count)|a\(attemptNumber)"
        var rng = SeededGenerator(seed: stableSeed(for: seedInput))
        var questions: [QuizQuestion] = [makeDefinitionQuestion(for: word, rng: &rng)]
        let blankQuestions = makeBlankQuestions(for: word, count: max(0, desiredCount - 1), rng: &rng)
        questions.append(contentsOf: blankQuestions)
        return Array(questions.prefix(desiredCount))
    }

    /// Curated quiz questions from WordPack JSON (1 definition + 2 blank, or
    /// whatever is in the file). On same-day retries, choice order is reshuffled
    /// to prevent memorizing positions.
    private func curatedQuestions(for word: Word, count: Int, attemptNumber: Int) -> [QuizQuestion]? {
        let date = quizDayISO()
        guard let presets = DailyWordsService.curatedQuiz(forWord: word.word, date: date),
              !presets.isEmpty else {
            return nil
        }
        let seedInput = "\(word.word.lowercased())|\(date)|curated|a\(attemptNumber)"
        var rng = SeededGenerator(seed: stableSeed(for: seedInput))
        let limited = Array(presets.prefix(count))
        return limited.map { preset in
            shuffledOptions(for: preset, rng: &rng)
        }
    }

    private func shuffledOptions(for preset: WordPackQuiz, rng: inout SeededGenerator) -> QuizQuestion {
        var indexed = Array(preset.options.enumerated())
        rng.shuffle(&indexed)
        let options = indexed.map { $0.element }
        let correctIndex = indexed.firstIndex(where: { $0.offset == preset.correctAnswerIndex })
            ?? max(0, min(preset.correctAnswerIndex, options.count - 1))
        return QuizQuestion(
            question: preset.question,
            options: options,
            correctAnswerIndex: correctIndex
        )
    }
    
    func startQuiz(for word: Word) -> Bool {
        print("Starting quiz for word: \(word.word)")
        quizAttemptsToday += 1
        saveAttemptsForToday()

        // Build 3 questions (attemptNumber reshuffles choices on same-day retries)
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
