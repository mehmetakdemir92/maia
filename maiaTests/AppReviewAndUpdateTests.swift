//
//  AppReviewAndUpdateTests.swift
//  maiaTests
//

import XCTest
@testable import maia

/// Review prompt gating (streak + cooldown) and update version comparison.
@MainActor
final class AppReviewAndUpdateTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "AppReviewAndUpdateTests")
        defaults.removePersistentDomain(forName: "AppReviewAndUpdateTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "AppReviewAndUpdateTests")
        defaults = nil
        super.tearDown()
    }

    // MARK: - Review prompt gating

    func testShouldPrompt_lowStreak_returnsFalse() {
        XCTAssertFalse(AppReviewPrompter.shouldPrompt(currentStreak: 2, defaults: defaults))
    }

    func testShouldPrompt_engagedUser_neverPromptedBefore_returnsTrue() {
        XCTAssertTrue(AppReviewPrompter.shouldPrompt(currentStreak: 3, defaults: defaults))
    }

    func testShouldPrompt_recentlyPrompted_returnsFalse() {
        AppReviewPrompter.recordPrompt(defaults: defaults)
        XCTAssertFalse(AppReviewPrompter.shouldPrompt(currentStreak: 10, defaults: defaults))
    }

    func testShouldPrompt_cooldownElapsed_returnsTrue() {
        let seventyDaysAgo = Calendar.current.date(byAdding: .day, value: -70, to: Date())!
        AppReviewPrompter.recordPrompt(now: seventyDaysAgo, defaults: defaults)
        XCTAssertTrue(AppReviewPrompter.shouldPrompt(currentStreak: 5, defaults: defaults))
    }

    // MARK: - Update version comparison

    func testIsVersionNewer_patchBump_returnsTrue() {
        XCTAssertTrue(AppUpdateChecker.isVersion("1.1.4", newerThan: "1.1.3"))
    }

    func testIsVersionNewer_sameVersion_returnsFalse() {
        XCTAssertFalse(AppUpdateChecker.isVersion("1.1.3", newerThan: "1.1.3"))
    }

    func testIsVersionNewer_installedIsNewer_returnsFalse() {
        XCTAssertFalse(AppUpdateChecker.isVersion("1.1.3", newerThan: "1.2.0"))
    }

    func testIsVersionNewer_numericNotLexicographic() {
        XCTAssertTrue(AppUpdateChecker.isVersion("1.1.10", newerThan: "1.1.9"))
    }

    func testIsVersionNewer_differentComponentCounts() {
        XCTAssertTrue(AppUpdateChecker.isVersion("1.2", newerThan: "1.1.9"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.1", newerThan: "1.1.0"))
    }
}
