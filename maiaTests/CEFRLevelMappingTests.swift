//
//  CEFRLevelMappingTests.swift
//  maiaTests
//

import XCTest
@testable import maia

/// Tests daily-word CEFR band selection (settings level → which bands appear in Today's 3 words).
final class CEFRLevelMappingTests: XCTestCase {

    func testPreferredBands_B2Plus_returnsTwoC1AndOneB2() {
        // Settings step 8 = "B2+" label; daily pick should be 2× C1 + 1× B2.
        XCTAssertEqual(
            CEFRLevelMapping.preferredBands(for: 8),
            ["c1", "c1", "b2"]
        )
    }

    func testPreferredBandsSummary_B2Plus_formatsUserFacingLabel() {
        XCTAssertEqual(
            CEFRLevelMapping.preferredBandsSummary(for: 8),
            "1× B2, 2× C1"
        )
    }

    func testSubstituteBands_B2Plus_neverFallsBackToB1() {
        let substitutes = CEFRLevelMapping.substituteBands(for: "c1", userLevel: 8)
        XCTAssertFalse(substitutes.contains("b1"))
        XCTAssertTrue(substitutes.contains("c2") || substitutes.contains("b2"))
    }

    func testMatchesPreferredBands_whenWordsMatchLevel_returnsTrue() {
        let words = [
            makeWord(lemma: "alpha", cefr: "c1"),
            makeWord(lemma: "beta", cefr: "c1"),
            makeWord(lemma: "gamma", cefr: "b2"),
        ]
        XCTAssertTrue(CEFRLevelMapping.matchesPreferredBands(words, userLevel: 8))
    }

    func testMatchesPreferredBands_whenDistributionWrong_returnsFalse() {
        let words = [
            makeWord(lemma: "alpha", cefr: "a1"),
            makeWord(lemma: "beta", cefr: "a2"),
            makeWord(lemma: "gamma", cefr: "b1"),
        ]
        XCTAssertFalse(CEFRLevelMapping.matchesPreferredBands(words, userLevel: 8))
    }

    // MARK: - Helpers

    private func makeWord(lemma: String, cefr: String) -> Word {
        Word(
            id: UUID.stable(from: lemma),
            word: lemma,
            definition: "Definition of \(lemma).",
            exampleSentence: "Example with \(lemma).",
            phonetic: nil,
            pronunciationAudioURL: nil,
            exampleSentence2: nil,
            exampleSentence3: nil,
            cefrLevel: cefr,
            domainTag: "general",
            partOfSpeech: "noun",
            registerTag: "neutral",
            frequencyBand: 2
        )
    }
}
