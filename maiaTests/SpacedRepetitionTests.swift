//
//  SpacedRepetitionTests.swift
//  maiaTests
//
//  Created by Mehmet Akdemir on 26.01.2026.
//

import XCTest
@testable import maia

final class SpacedRepetitionTests: XCTestCase {
    var spacedRepetition: SpacedRepetitionManager!
    var progressManager: WordProgressManager!
    let testWordId = UUID()
    
    override func setUp() {
        super.setUp()
        spacedRepetition = SpacedRepetitionManager()
        progressManager = WordProgressManager()
    }
    
    override func tearDown() {
        spacedRepetition = nil
        progressManager = nil
        super.tearDown()
    }
    
    // MARK: - Grade Mapping Tests
    
    func testGradeMapping_AllWrong() {
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 0, total: 10), 0)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 1, total: 10), 0)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 2, total: 10), 0)
    }
    
    func testGradeMapping_LowScores() {
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 3, total: 10), 1)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 4, total: 10), 1)
    }
    
    func testGradeMapping_MediumScores() {
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 5, total: 10), 2)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 6, total: 10), 2)
    }
    
    func testGradeMapping_GoodScores() {
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 7, total: 10), 3)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 8, total: 10), 3)
    }
    
    func testGradeMapping_ExcellentScores() {
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 9, total: 10), 4)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 10, total: 10), 5)
    }
    
    func testGradeMapping_AdaptiveLength_Perfect() {
        // 3/3 correct = 100% accuracy
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 3, total: 3), 5)
    }
    
    func testGradeMapping_AdaptiveLength_HighAccuracy() {
        // 2/3 correct = 67% accuracy -> grade 3
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 2, total: 3), 3)
        // 3/4 correct = 75% accuracy -> grade 3
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 3, total: 4), 3)
    }
    
    // MARK: - SM-2 Algorithm Tests
    
    func testFailedReview_ResetsRepetitions() {
        let initial = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 10, repetitions: 5)
        let updated = spacedRepetition.updateProgress(initial, quality: 2) // q < 3
        
        XCTAssertEqual(updated.repetitions, 0)
        XCTAssertEqual(updated.intervalDays, 1)
        XCTAssertEqual(updated.ease, 2.3, accuracy: 0.01) // 2.5 - 0.2
    }
    
    func testFailedReview_MinEaseBound() {
        let initial = WordProgress(wordId: testWordId, ease: 1.3, intervalDays: 5, repetitions: 2)
        let updated = spacedRepetition.updateProgress(initial, quality: 0) // q < 3
        
        XCTAssertEqual(updated.ease, 1.3, accuracy: 0.01) // Should not go below 1.3
    }
    
    func testFirstSuccessfulReview() {
        let initial = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 0, repetitions: 0)
        let updated = spacedRepetition.updateProgress(initial, quality: 3) // q >= 3
        
        XCTAssertEqual(updated.repetitions, 1)
        XCTAssertEqual(updated.intervalDays, 1)
        XCTAssertEqual(updated.ease, 2.5, accuracy: 0.01) // No change for q=3
    }
    
    func testSecondSuccessfulReview() {
        let initial = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 1, repetitions: 1)
        let updated = spacedRepetition.updateProgress(initial, quality: 3)
        
        XCTAssertEqual(updated.repetitions, 2)
        XCTAssertEqual(updated.intervalDays, 6)
    }
    
    func testThirdSuccessfulReview() {
        let initial = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 6, repetitions: 2)
        let updated = spacedRepetition.updateProgress(initial, quality: 3)
        
        XCTAssertEqual(updated.repetitions, 3)
        XCTAssertEqual(updated.intervalDays, 15) // round(6 * 2.5) = 15
    }
    
    func testQuality4_IncreasesEase() {
        let initial = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 10, repetitions: 3)
        let updated = spacedRepetition.updateProgress(initial, quality: 4)
        
        XCTAssertEqual(updated.ease, 2.55, accuracy: 0.01) // 2.5 + 0.05
    }
    
    func testQuality5_IncreasesEaseMore() {
        let initial = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 10, repetitions: 3)
        let updated = spacedRepetition.updateProgress(initial, quality: 5)
        
        XCTAssertEqual(updated.ease, 2.6, accuracy: 0.01) // 2.5 + 0.10
    }
    
    func testMaxEaseBound() {
        let initial = WordProgress(wordId: testWordId, ease: 3.5, intervalDays: 10, repetitions: 5)
        let updated = spacedRepetition.updateProgress(initial, quality: 5)
        
        XCTAssertEqual(updated.ease, 3.5, accuracy: 0.01) // Should not exceed 3.5
    }
    
    func testRepeatedFailures_DecreasesEase() {
        var progress = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 10, repetitions: 5)
        
        // First failure
        progress = spacedRepetition.updateProgress(progress, quality: 0)
        XCTAssertEqual(progress.ease, 2.3, accuracy: 0.01)
        
        // Second failure
        progress = spacedRepetition.updateProgress(progress, quality: 1)
        XCTAssertEqual(progress.ease, 2.1, accuracy: 0.01)
        
        // Third failure
        progress = spacedRepetition.updateProgress(progress, quality: 0)
        XCTAssertEqual(progress.ease, 1.9, accuracy: 0.01)
    }
    
    func testRepeatedPerfectScores() {
        var progress = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 0, repetitions: 0)
        
        // First perfect (q=5)
        progress = spacedRepetition.updateProgress(progress, quality: 5)
        XCTAssertEqual(progress.repetitions, 1)
        XCTAssertEqual(progress.intervalDays, 1)
        XCTAssertEqual(progress.ease, 2.6, accuracy: 0.01)
        
        // Second perfect
        progress = spacedRepetition.updateProgress(progress, quality: 5)
        XCTAssertEqual(progress.repetitions, 2)
        XCTAssertEqual(progress.intervalDays, 6)
        XCTAssertEqual(progress.ease, 2.7, accuracy: 0.01)
        
        // Third perfect
        progress = spacedRepetition.updateProgress(progress, quality: 5)
        XCTAssertEqual(progress.repetitions, 3)
        XCTAssertEqual(progress.intervalDays, 16) // round(6 * 2.7) = 16
        XCTAssertEqual(progress.ease, 2.8, accuracy: 0.01)
    }
    
    // MARK: - Next Due Date Tests
    
    func testScheduleNext_OneDay() {
        let progress = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 1, repetitions: 1)
        let now = Date()
        let nextDue = spacedRepetition.scheduleNext(progress: progress, now: now)
        
        let calendar = Calendar.current
        let daysDifference = calendar.dateComponents([.day], from: now, to: nextDue).day ?? 0
        XCTAssertEqual(daysDifference, 1)
    }
    
    func testScheduleNext_MultipleDays() {
        let progress = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 10, repetitions: 3)
        let now = Date()
        let nextDue = spacedRepetition.scheduleNext(progress: progress, now: now)
        
        let calendar = Calendar.current
        let daysDifference = calendar.dateComponents([.day], from: now, to: nextDue).day ?? 0
        XCTAssertEqual(daysDifference, 10)
    }
    
    func testIsDue_True() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let progress = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 1, repetitions: 1, nextDueAt: yesterday)
        
        XCTAssertTrue(spacedRepetition.isDue(progress))
    }
    
    func testIsDue_False() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        let progress = WordProgress(wordId: testWordId, ease: 2.5, intervalDays: 1, repetitions: 1, nextDueAt: tomorrow)
        
        XCTAssertFalse(spacedRepetition.isDue(progress))
    }
    
    // MARK: - Edge Cases
    
    func testBorderlineCounts() {
        // Exactly at boundaries
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 2, total: 10), 0)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 3, total: 10), 1)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 4, total: 10), 1)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 5, total: 10), 2)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 6, total: 10), 2)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 7, total: 10), 3)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 8, total: 10), 3)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 9, total: 10), 4)
        XCTAssertEqual(spacedRepetition.gradeFromCount(correct: 10, total: 10), 5)
    }
    
    func testIntervalRounding() {
        let initial = WordProgress(wordId: testWordId, ease: 2.3, intervalDays: 7, repetitions: 3)
        let updated = spacedRepetition.updateProgress(initial, quality: 3)
        
        // round(7 * 2.3) = round(16.1) = 16
        XCTAssertEqual(updated.intervalDays, 16)
    }
    
    func testZeroTotalQuestions() {
        // Should handle gracefully
        let grade = spacedRepetition.gradeFromCount(correct: 0, total: 0)
        XCTAssertEqual(grade, 0)
    }
}
