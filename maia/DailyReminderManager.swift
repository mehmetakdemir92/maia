//
//  DailyReminderManager.swift
//  maia
//
// The cue in the habit loop. Everything else was already here — a finite daily
// slot, a hard 24h gate, a streak — but nothing brought the learner back; they
// had to remember on their own.
//
// Local notifications only: no push server, no FCM, no cost.
//

import Combine
import Foundation
import UserNotifications

@MainActor
final class DailyReminderManager: ObservableObject {

    static let shared = DailyReminderManager()

    /// Reminders are scheduled as this many discrete daily requests rather than
    /// one repeating trigger. A repeating `UNCalendarNotificationTrigger` cannot
    /// skip a single occurrence, and skipping is the whole point: once today's
    /// session is done the learner must not be nagged about it. iOS keeps at
    /// most 64 pending requests per app, so two weeks is comfortably within
    /// budget and re-arms on every launch.
    private static let scheduledDays = 15

    /// Last call of the day, carrying the streak/state line. The study day
    /// does not roll over until 04:00, so the true final moment is past
    /// midnight — an hour nobody should be pushed at. 21:30 still leaves an
    /// evening to act in.
    private static let lastCallHour = 21
    private static let lastCallMinute = 30

    private static let identifierPrefix = "daily-reminder-"
    private static let wordNudgeIdentifier = "word-nudge-today"
    private static let enabledKey = "dailyReminderEnabled"
    private static let hourKey = "dailyReminderHour"
    private static let minuteKey = "dailyReminderMinute"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var hour: Int
    @Published private(set) var minute: Int
    /// True when the user has turned reminders off at the OS level. The in-app
    /// toggle cannot fix that, so the UI has to point at system Settings.
    @Published private(set) var isBlockedBySystem = false

    /// What the copy needs to know about the learner's streak.
    struct StreakSnapshot {
        /// Streak as of now. Zero implies yesterday was missed: a completed
        /// yesterday keeps the count alive until the day rolls over.
        var current: Int = 0
        var best: Int = 0
        /// Whether the day before yesterday was completed. With `current == 0`
        /// this is the repairable case — finishing today makes yesterday the
        /// recoverable gap, and the rewarded video can then bridge it.
        var completedDayBeforeYesterday: Bool = false
    }

    /// Supplies the streak at scheduling time. Injected by MainTabView, the
    /// only place holding both this singleton and the StreakManager — the
    /// scheduler must not recompute a streak from stored dates and end up
    /// with its own second answer.
    var streakProvider: (() -> StreakSnapshot)?

    /// A word from today's slot, for the evening nudge. Injected by
    /// WordOfTheDayManager, which owns the loaded slot.
    var focusWordProvider: (() -> String?)?

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let storedHour = defaults.object(forKey: Self.hourKey) as? Int
        let storedMinute = defaults.object(forKey: Self.minuteKey) as? Int
        // Daytime nudge, so it defaults to the middle of the day rather
        // than the evening — the evening belongs to the last call.
        hour = storedHour ?? 13
        minute = storedMinute ?? 0
    }

    /// Wall-clock time of the reminder, as a Date for SwiftUI's DatePicker.
    var reminderTime: Date {
        var parts = DateComponents()
        parts.hour = hour
        parts.minute = minute
        return Calendar.current.date(from: parts) ?? Date()
    }

    // MARK: - Toggling

    /// Turns reminders on, asking for permission the first time. Returns false
    /// when the learner declines or has denied notifications in system Settings.
    @discardableResult
    func enable() async -> Bool {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else {
            isBlockedBySystem = true
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return false
        }

        isBlockedBySystem = false
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        await refreshSchedule()
        return true
    }

    func disable() {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        clearPending()
    }

    func setTime(hour: Int, minute: Int) async {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        UserDefaults.standard.set(self.hour, forKey: Self.hourKey)
        UserDefaults.standard.set(self.minute, forKey: Self.minuteKey)
        await refreshSchedule()
    }

    // MARK: - Scheduling

    /// Rebuilds the pending reminders.
    ///
    /// - Parameter skippingToday: pass true right after a session is finished,
    ///   so the learner is not reminded to do something they already did.
    func refreshSchedule(skippingToday: Bool = false) async {
        clearPending()
        guard isEnabled else { return }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            isBlockedBySystem = true
            return
        }
        isBlockedBySystem = false

        let calendar = Calendar.current
        let now = Date()
        let streak = streakProvider?() ?? StreakSnapshot()

        for offset in 0..<Self.scheduledDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireDate = calendar.date(
                    bySettingHour: Self.lastCallHour,
                    minute: Self.lastCallMinute,
                    second: 0,
                    of: day
                  )
            else { continue }

            // Never schedule in the past — today's time may already have passed.
            guard fireDate > now else { continue }

            // The study day rolls over at 04:00, not midnight, so "today" for
            // the gate is not the same as today's calendar date. Compare study
            // days, otherwise an evening session would still leave tomorrow's
            // 01:00 reminder pointing at a slot that is already finished.
            if skippingToday, CurriculumStateManager.isSameStudyDay(fireDate, now) {
                continue
            }

            await add(
                identifier: "\(Self.identifierPrefix)\(offset)",
                copy: copy(forDayOffset: offset, streak: streak),
                at: fireDate,
                hour: Self.lastCallHour,
                minute: Self.lastCallMinute
            )
        }

        // Daytime nudge at the learner's chosen hour, TODAY ONLY. Naming one
        // of today's words needs the slot actually loaded, and the word only
        // holds while the slot does — placing it on a later day risks naming a
        // word they have since moved past. Skipped entirely when no word is
        // available rather than sending a sentence with a hole in it.
        if !skippingToday,
           let word = focusWordProvider?(),
           !word.isEmpty,
           let nudgeDate = calendar.date(
            bySettingHour: hour, minute: minute, second: 0, of: now
           ),
           nudgeDate > now {
            await add(
                identifier: Self.wordNudgeIdentifier,
                copy: Copy(
                    title: String(localized: "Today's words are ready"),
                    body: String(
                        format: String(localized: "Today looks like a great day to lock in the word \"%@\" ☀️"),
                        word
                    )
                ),
                at: nudgeDate,
                hour: hour,
                minute: minute
            )
        }
    }

    // MARK: - Copy

    private struct Copy {
        let title: String
        let body: String
    }

    /// Wording for the reminder that far out.
    ///
    /// Only offset 0 may mention the streak. `currentStreak` is measured
    /// against today, so it decays on its own: a five-day streak written into
    /// tomorrow's request would read "your 5-day streak" on a day the streak
    /// is already zero. Later days therefore use lines that stay true however
    /// long the learner stays away, keyed off the best streak rather than the
    /// live one.
    private func copy(forDayOffset offset: Int, streak: StreakSnapshot) -> Copy {
        let title = String(localized: "Today's words are ready")

        guard offset == 0 else {
            return Copy(title: title, body: rebuildingBody(best: streak.best))
        }

        if streak.current >= 1 {
            return Copy(
                title: title,
                body: String(
                    format: String(localized: "Your %lld-day streak looks great — protect it with a short quiz ✨💪"),
                    Int64(streak.current)
                )
            )
        }

        // current == 0 means yesterday was missed. If the day before it was
        // done, the run is still rescuable: finishing today makes yesterday
        // the recoverable gap, which the rewarded video can then bridge.
        if streak.completedDayBeforeYesterday {
            return Copy(
                title: title,
                body: String(localized: "Finish the short quiz and your streak can still be saved. I believe in you 🥹")
            )
        }

        return Copy(title: title, body: rebuildingBody(best: streak.best))
    }

    /// Someone who has held a streak before is rebuilding one; someone who
    /// never has is being invited to start. Both stay true over time.
    private func rebuildingBody(best: Int) -> String {
        best >= 1
            ? String(localized: "It's never too late to start a new streak 🙂")
            : String(localized: "A good day to add a small habit that pays you back 😌")
    }

    private func add(identifier: String, copy: Copy, at date: Date, hour: Int, minute: Int) async {
        let content = UNMutableNotificationContent()
        content.title = copy.title
        content.body = copy.body
        content.sound = .default

        var parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        parts.hour = hour
        parts.minute = minute

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Re-arms the rolling window. Safe to call on every foreground: it only
    /// rewrites our own requests.
    func refreshOnForeground() async {
        guard isEnabled else { return }
        await refreshSchedule()
    }

    // MARK: - Private

    private func clearPending() {
        var ids = (0..<Self.scheduledDays).map { "\(Self.identifierPrefix)\($0)" }
        ids.append(Self.wordNudgeIdentifier)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            // Only system Settings can undo this; asking again is a no-op.
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }
}
