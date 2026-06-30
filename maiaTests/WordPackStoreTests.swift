//
//  WordPackStoreTests.swift
//  maiaTests
//

import XCTest
@testable import maia

/// Tests how 12 curated WordPack words become the 3 daily words for a user level.
@MainActor
final class WordPackStoreTests: XCTestCase {

    private let testDate = "2099-01-15"

    func testMonthKey_extractsYearAndMonth() {
        XCTAssertEqual(WordPackStore.monthKey(from: "2026-07-15"), "2026-07")
        XCTAssertNil(WordPackStore.monthKey(from: "invalid"))
    }

    func testSelectByPreferredBands_B2Plus_picksTwoC1AndOneB2() {
        let pool = [
            makeEntry(word: "c1-alpha", cefr: "c1"),
            makeEntry(word: "c1-beta", cefr: "c1"),
            makeEntry(word: "b2-gamma", cefr: "b2"),
            makeEntry(word: "b2-delta", cefr: "b2"),
            makeEntry(word: "b1-trap", cefr: "b1"),
        ]

        let picked = WordPackStore.selectByPreferredBands(pool, userLevel: 8, date: testDate)

        XCTAssertEqual(picked.count, 3)
        let bands = picked.map { $0.cefrLevel.lowercased() }.sorted()
        XCTAssertEqual(bands, ["b2", "c1", "c1"])
        XCTAssertFalse(picked.contains { $0.word == "b1-trap" })
    }

    func testSelectByPreferredBands_B2Plus_whenC1Missing_usesFallbackWithoutB1() {
        // Preferred bands want C1, but pool only has B2 + C2 (+ a B1 trap word).
        let pool = [
            makeEntry(word: "b2-one", cefr: "b2"),
            makeEntry(word: "b2-two", cefr: "b2"),
            makeEntry(word: "c2-one", cefr: "c2"),
            makeEntry(word: "c2-two", cefr: "c2"),
            makeEntry(word: "b1-trap", cefr: "b1"),
        ]

        let picked = WordPackStore.selectByPreferredBands(pool, userLevel: 8, date: testDate)

        XCTAssertEqual(picked.count, 3)
        let bands = Set(picked.map { $0.cefrLevel.lowercased() })
        XCTAssertFalse(bands.contains("b1"), "B2+ should not fall back to B1 when C2/B2 exist")
        XCTAssertTrue(bands.contains("b2"))
        XCTAssertTrue(bands.contains("c2"))
    }

    func testSelectByPreferredBands_isDeterministicForSameDateAndPool() {
        let pool = [
            makeEntry(word: "c1-alpha", cefr: "c1"),
            makeEntry(word: "c1-beta", cefr: "c1"),
            makeEntry(word: "b2-gamma", cefr: "b2"),
        ]

        let first = WordPackStore.selectByPreferredBands(pool, userLevel: 8, date: testDate)
        let second = WordPackStore.selectByPreferredBands(pool, userLevel: 8, date: testDate)

        XCTAssertEqual(first.map(\.word), second.map(\.word))
    }

    func testSelectByPreferredBands_resultMatchesCEFRMappingRules() {
        let pool = miniDayPool()
        let picked = WordPackStore.selectByPreferredBands(pool, userLevel: 8, date: testDate)
        let words = picked.map { $0.toWord() }

        XCTAssertEqual(words.count, 3)
        XCTAssertTrue(CEFRLevelMapping.matchesPreferredBands(words, userLevel: 8))
    }

    func testWordPackJSON_decodesAndSelectsThreeWords() throws {
        let data = Data(minimalWordPackJSON.utf8)
        let pack = try JSONDecoder().decode(WordPack.self, from: data)

        XCTAssertEqual(pack.month, "2099-01")
        let entries = pack.days["2099-01-01"]?.words ?? []
        XCTAssertEqual(entries.count, 6)

        let picked = WordPackStore.selectByPreferredBands(entries, userLevel: 8, date: "2099-01-01")
        XCTAssertEqual(picked.count, 3)
        XCTAssertEqual(
            picked.map { $0.cefrLevel.lowercased() }.sorted(),
            ["b2", "c1", "c1"]
        )
    }

    // MARK: - Fixtures

    private func miniDayPool() -> [WordPackWord] {
        [
            makeEntry(word: "c1-one", cefr: "c1"),
            makeEntry(word: "c1-two", cefr: "c1"),
            makeEntry(word: "b2-one", cefr: "b2"),
            makeEntry(word: "a2-noise", cefr: "a2"),
        ]
    }

    private func makeEntry(word: String, cefr: String) -> WordPackWord {
        WordPackWord(
            word: word,
            cefrLevel: cefr,
            definition: "Definition of \(word).",
            examples: [
                "First example with \(word).",
                "Second example with \(word).",
                "Third example with \(word).",
            ],
            quiz: [
                WordPackQuiz(
                    type: "definition",
                    question: "What does \"\(word)\" mean?",
                    options: ["A", "B", "C", "D"],
                    correctAnswerIndex: 0
                ),
            ],
            phonetic: nil,
            partOfSpeech: "noun",
            domainTag: "general",
            registerTag: "neutral",
            frequencyBand: 2
        )
    }

    private var minimalWordPackJSON: String {
        """
        {
          "month": "2099-01",
          "days": {
            "2099-01-01": {
              "words": [
                {
                  "word": "c1-alpha",
                  "cefrLevel": "c1",
                  "definition": "First C1 word.",
                  "examples": ["One.", "Two.", "Three."],
                  "quiz": [{
                    "type": "definition",
                    "question": "Q?",
                    "options": ["First C1 word.", "Wrong", "Wrong", "Wrong"],
                    "correctAnswerIndex": 0
                  }]
                },
                {
                  "word": "c1-beta",
                  "cefrLevel": "c1",
                  "definition": "Second C1 word.",
                  "examples": ["One.", "Two.", "Three."],
                  "quiz": [{
                    "type": "definition",
                    "question": "Q?",
                    "options": ["Second C1 word.", "Wrong", "Wrong", "Wrong"],
                    "correctAnswerIndex": 0
                  }]
                },
                {
                  "word": "b2-gamma",
                  "cefrLevel": "b2",
                  "definition": "B2 word.",
                  "examples": ["One.", "Two.", "Three."],
                  "quiz": [{
                    "type": "definition",
                    "question": "Q?",
                    "options": ["B2 word.", "Wrong", "Wrong", "Wrong"],
                    "correctAnswerIndex": 0
                  }]
                },
                {
                  "word": "b2-delta",
                  "cefrLevel": "b2",
                  "definition": "Another B2 word.",
                  "examples": ["One.", "Two.", "Three."],
                  "quiz": [{
                    "type": "definition",
                    "question": "Q?",
                    "options": ["Another B2 word.", "Wrong", "Wrong", "Wrong"],
                    "correctAnswerIndex": 0
                  }]
                },
                {
                  "word": "c2-epsilon",
                  "cefrLevel": "c2",
                  "definition": "C2 word.",
                  "examples": ["One.", "Two.", "Three."],
                  "quiz": [{
                    "type": "definition",
                    "question": "Q?",
                    "options": ["C2 word.", "Wrong", "Wrong", "Wrong"],
                    "correctAnswerIndex": 0
                  }]
                },
                {
                  "word": "b1-trap",
                  "cefrLevel": "b1",
                  "definition": "Should not be picked for B2+.",
                  "examples": ["One.", "Two.", "Three."],
                  "quiz": [{
                    "type": "definition",
                    "question": "Q?",
                    "options": ["Trap.", "Wrong", "Wrong", "Wrong"],
                    "correctAnswerIndex": 0
                  }]
                }
              ]
            }
          }
        }
        """
    }
}
