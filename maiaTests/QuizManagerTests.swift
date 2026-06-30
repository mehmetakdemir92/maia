//
//  QuizManagerTests.swift
//  maiaTests
//

import XCTest
@testable import maia

/// Quiz pass/fail and retry rules (3 questions, 2 correct to pass, max 3 attempts/day).
final class QuizManagerTests: XCTestCase {

    private var manager: QuizManager!

    override func setUp() {
        super.setUp()
        manager = QuizManager()
        manager.quizAttemptsToday = 0
    }

    override func tearDown() {
        manager = nil
        super.tearDown()
    }

    func testHasPassed_twoOfThreeCorrect_passes() {
        manager.correctAnswers = 2
        XCTAssertTrue(manager.hasPassed())
    }

    func testHasPassed_oneOfThreeCorrect_fails() {
        manager.correctAnswers = 1
        XCTAssertFalse(manager.hasPassed())
    }

    func testHasPassed_threeOfThreeCorrect_passes() {
        manager.correctAnswers = 3
        XCTAssertTrue(manager.hasPassed())
    }

    func testCanRetry_afterFailing_withAttemptsRemaining_allowsRetry() {
        manager.correctAnswers = 1
        manager.quizAttemptsToday = 1
        XCTAssertTrue(manager.canRetry())
    }

    func testCanRetry_afterPassing_disallowsRetry() {
        manager.correctAnswers = 2
        manager.quizAttemptsToday = 1
        XCTAssertFalse(manager.canRetry())
    }

    func testCanRetry_whenMaxAttemptsReached_disallowsRetry() {
        manager.correctAnswers = 0
        manager.quizAttemptsToday = 3
        XCTAssertFalse(manager.canRetry())
    }
}
