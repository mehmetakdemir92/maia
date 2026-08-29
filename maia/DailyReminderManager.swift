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
    private static let scheduledDays = 14

    private static let identifierPrefix = "daily-reminder-"
    private static let enabledKey = "dailyReminderEnabled"
    private static let hourKey = "dailyReminderHour"
    private static let minuteKey = "dailyReminderMinute"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var hour: Int
    @Published private(set) var minute: Int
    /// True when the user has turned reminders off at the OS level. The in-app
    /// toggle cannot fix that, so the UI has to point at system Settings.
    @Published private(set) var isBlockedBySystem = false

    private init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        let storedHour = defaults.object(forKey: Self.hourKey) as? Int
        let storedMinute = defaults.object(forKey: Self.minuteKey) as? Int
        hour = storedHour ?? 20
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
        let center = UNUserNotificationCenter.current()

        for offset in 0..<Self.scheduledDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireDate = calendar.date(
                    bySettingHour: hour, minute: minute, second: 0, of: day
                  )
            else { continue }

            // Never schedule in the past — today's time may already have passed.
            guard fireDate > now else { continue }

            // The study day rolls over at 04:00, not midnight, so "today" for
            // the gate is not the same as today's calendar date. Compare study
            // days, otherwise an evening session would still leave tomorrow's
            // 01:00 reminder pointing at a slot that is already finished.
            if skippingToday,
               CurriculumStateManager.isSameStudyDay(fireDate, now) {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "Today's words are ready")
            content.body = String(localized: "Five new words and a quick review. Keep your streak alive.")
            content.sound = .default

            var parts = calendar.dateComponents([.year, .month, .day], from: fireDate)
            parts.hour = hour
            parts.minute = minute

            let request = UNNotificationRequest(
                identifier: "\(Self.identifierPrefix)\(offset)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Re-arms the rolling window. Safe to call on every foreground: it only
    /// rewrites our own requests.
    func refreshOnForeground() async {
        guard isEnabled else { return }
        await refreshSchedule()
    }

    // MARK: - Private

    private func clearPending() {
        let ids = (0..<Self.scheduledDays).map { "\(Self.identifierPrefix)\($0)" }
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
