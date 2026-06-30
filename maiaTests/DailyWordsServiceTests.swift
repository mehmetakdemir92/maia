//
//  DailyWordsServiceTests.swift
//  maiaTests
//

import XCTest
@testable import maia

/// Validates cached daily words before they are shown, and Istanbul calendar day boundaries.
@MainActor
final class DailyWordsServiceTests: XCTestCase {

    // MARK: - Word set quality (shown on Today)

    func testIsUsableWordSet_threeValidWords_returnsTrue() {
        let words = [
            makeWord(lemma: "absorb", example: "Plants absorb sunlight."),
            makeWord(lemma: "ability", example: "She has the ability to learn."),
            makeWord(lemma: "achieve", example: "They achieve their goals."),
        ]

        XCTAssertTrue(DailyWordsService.isUsableWordSet(words))
    }

    func testIsUsableWordSet_fewerThanThree_returnsFalse() {
        let words = [makeWord(lemma: "absorb", example: "Plants absorb sunlight.")]
        XCTAssertFalse(DailyWordsService.isUsableWordSet(words))
    }

    func testIsUsableWordSet_placeholderTODO_returnsFalse() {
        let words = [
            makeWord(lemma: "absorb", example: "Plants absorb sunlight."),
            makeWord(lemma: "ability", example: "TODO: write example."),
            makeWord(lemma: "achieve", example: "They achieve their goals."),
        ]

        XCTAssertFalse(DailyWordsService.isUsableWordSet(words))
    }

    func testExampleIncludesHeadword_inflectedForm_countsAsValid() {
        let word = makeWord(lemma: "achieve", example: "She achieved great results.")
        XCTAssertTrue(DailyWordsService.exampleIncludesHeadword(word))
    }

    func testExampleIncludesHeadword_missingHeadword_returnsFalse() {
        let word = makeWord(lemma: "absorb", example: "The meeting starts at nine.")
        XCTAssertFalse(DailyWordsService.exampleIncludesHeadword(word))
    }

    // MARK: - Istanbul day boundary (daily reset + ad counters)

    func testCalendarDayISO_usesEuropeIstanbulTimezone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        // 2026-06-30 21:00 UTC = 2026-07-01 00:00 in Istanbul (UTC+3)
        let instant = utc.date(from: DateComponents(
            year: 2026, month: 6, day: 30, hour: 21, minute: 0
        ))!

        XCTAssertEqual(WordOfTheDayManager.calendarDayISO(for: instant), "2026-07-01")
    }

    func testCalendarDayISO_sameInstant_differsFromUTCDate() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let instant = utc.date(from: DateComponents(
            year: 2026, month: 6, day: 30, hour: 21, minute: 0
        ))!

        let utcDay = utc.component(.day, from: instant)
        XCTAssertEqual(utcDay, 30)
        XCTAssertEqual(WordOfTheDayManager.calendarDayISO(for: instant), "2026-07-01")
    }

    // MARK: - Helpers

    private func makeWord(lemma: String, example: String) -> Word {
        Word(
            id: UUID.stable(from: lemma),
            word: lemma,
            definition: "Definition of \(lemma).",
            exampleSentence: example,
            cefrLevel: "b1"
        )
    }
}
