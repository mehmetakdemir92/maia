//
//  StreakBridgeTests.swift
//  maiaTests
//

import XCTest
@testable import maia

/// The rewarded video is a bridge between two real streaks, never a free day.
/// These cover the boundaries of that rule.
@MainActor
final class StreakBridgeTests: XCTestCase {

    private let now = Date()

    /// Day key `offset` days before today, in the app's study-day space.
    private func key(_ offset: Int) -> String {
        let today = CurriculumStateManager.studyDayStart(for: now)
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: today) ?? today
        return CurriculumStateManager.studyDayISO(for: date)
    }

    private func keys(_ offsets: [Int]) -> Set<String> {
        Set(offsets.map(key))
    }

    private func gapOffsets(_ completed: Set<String>) -> [Int] {
        offsets(
            of: StreakManager.bridgeableGap(completedDayKeys: completed, asOf: now),
            relativeTo: now
        )
    }

    private func offsets(of dates: [Date], relativeTo now: Date) -> [Int] {
        let today = CurriculumStateManager.studyDayStart(for: now)
        return dates.map {
            Calendar.current.dateComponents([.day], from: $0, to: today).day ?? -1
        }
    }

    // MARK: No live streak

    func testNoStreakAtAllOffersNoBridge() {
        XCTAssertEqual(gapOffsets([]), [])
    }

    /// The old behaviour handed out a free day here. A video must not be able
    /// to start a streak from nothing.
    func testStreakWithNothingBeforeItOffersNoBridge() {
        // today, -1, -2 completed; nothing earlier ever.
        XCTAssertEqual(gapOffsets(keys([0, 1, 2])), [])
    }

    func testLapsedStreakOffersNoBridge() {
        // Last activity was a week ago: no live streak to bridge from.
        XCTAssertEqual(gapOffsets(keys([7, 8, 9])), [])
    }

    // MARK: Valid bridges

    func testOneDayGapBridges() {
        // streak: today, -1   gap: -2   earlier streak: -3, -4
        XCTAssertEqual(gapOffsets(keys([0, 1, 3, 4])), [2])
    }

    func testTwoDayGapBridges() {
        // streak: today   gap: -1, -2   earlier streak: -3
        XCTAssertEqual(gapOffsets(keys([0, 3])), [2, 1])
    }

    func testThreeDayGapBridges() {
        // streak: today   gap: -1, -2, -3   earlier streak: -4
        XCTAssertEqual(gapOffsets(keys([0, 4])), [3, 2, 1])
    }

    /// Streak anchored on yesterday (today not studied yet) still counts.
    func testStreakAnchoredOnYesterdayBridges() {
        XCTAssertEqual(gapOffsets(keys([1, 3])), [2])
    }

    // MARK: Cap

    func testFourDayGapIsTooLongToBridge() {
        // streak: today   gap: -1…-4   earlier streak: -5
        XCTAssertEqual(gapOffsets(keys([0, 5])), [])
    }

    func testGapLongerThanCapIsNotPartiallyBridged() {
        XCTAssertEqual(gapOffsets(keys([0, 9, 10])), [])
    }

    // MARK: Ordering

    func testBridgeDatesAreOldestFirst() {
        let dates = StreakManager.bridgeableGap(completedDayKeys: keys([0, 4]), asOf: now)
        XCTAssertEqual(dates, dates.sorted())
    }
}

/// Why the streak calendar anchors its cells at midday.
@MainActor
final class StudyDayAnchorTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testMiddayResolvesToItsOwnStudyDay() {
        XCTAssertEqual(
            CurriculumStateManager.studyDayISO(for: date(2026, 8, 30, hour: 12)),
            "2026-08-30"
        )
    }

    /// The trap the calendar used to fall into: midnight is before the 04:00
    /// reset, so it belongs to the previous study day.
    func testMidnightResolvesToThePreviousStudyDay() {
        XCTAssertEqual(
            CurriculumStateManager.studyDayISO(for: date(2026, 8, 30, hour: 0)),
            "2026-08-29"
        )
    }

    func testJustAfterResetHourResolvesToItsOwnStudyDay() {
        XCTAssertEqual(
            CurriculumStateManager.studyDayISO(for: date(2026, 8, 30, hour: 4)),
            "2026-08-30"
        )
    }
}
