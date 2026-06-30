//
//  WordPoolEntryTests.swift
//  maiaTests
//

import XCTest
@testable import maia

/// Parser for `DailyWordPool.txt` lines (word pack generation source file).
final class WordPoolEntryTests: XCTestCase {

    func testParseLine_pipeDelimited_parsesAllFields() {
        let entry = WordPoolEntry.parseLine("absorb|b1|general|verb|neutral|3")

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.word, "absorb")
        XCTAssertEqual(entry?.cefrLevel, "b1")
        XCTAssertEqual(entry?.domainTag, "general")
        XCTAssertEqual(entry?.partOfSpeech, "verb")
        XCTAssertEqual(entry?.registerTag, "neutral")
        XCTAssertEqual(entry?.frequencyBand, 3)
    }

    func testParseLine_legacySingleWord_noMetadata() {
        let entry = WordPoolEntry.parseLine("hello")

        XCTAssertEqual(entry?.word, "hello")
        XCTAssertNil(entry?.cefrLevel)
        XCTAssertNil(entry?.frequencyBand)
    }

    func testParseLine_commentOrEmpty_returnsNil() {
        XCTAssertNil(WordPoolEntry.parseLine("# Günlük kelime havuzu"))
        XCTAssertNil(WordPoolEntry.parseLine(""))
        XCTAssertNil(WordPoolEntry.parseLine("   "))
    }

    func testParseLine_trailingEmptyFields_allowed() {
        let entry = WordPoolEntry.parseLine("agree|a1|general|verb||")

        XCTAssertEqual(entry?.word, "agree")
        XCTAssertEqual(entry?.cefrLevel, "a1")
        XCTAssertNil(entry?.registerTag)
        XCTAssertNil(entry?.frequencyBand)
    }

    func testParseLine_cefrLevelIsLowercased() {
        let entry = WordPoolEntry.parseLine("Ability|A2|general|noun|neutral|2")
        XCTAssertEqual(entry?.cefrLevel, "a2")
    }
}
