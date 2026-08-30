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
// There is no in-app switch. Permission is the switch: anyone who grants it
// gets reminders, anyone who declines gets none, and iOS Settings is where
// that is changed. One preference fewer to store, explain and keep in sync.
//

import Combine
import Foundation
import UserNotifications

@MainActor
final class DailyReminderManager: ObservableObject {

    static let shared = DailyReminderManager()

    /// Days after the last app open on which to speak up — not every day.
    ///
    /// A daily ping at a fixed hour is what gets notifications switched off:
    /// it stops carrying information and becomes wallpaper, and someone who
    /// has drifted away reads fourteen identical nudges as nagging. Backing
    /// off — tomorrow, then three days, a week, a fortnight — keeps each one
    /// worth reading, and every step says something different.
    ///
    /// The offsets are days-since-last-open for free: the window is rebuilt on
    /// every open, so a request this far out only survives if nobody came back.
    private static let scheduleOffsets = [0, 1, 3, 7, 14]

    /// Last call of the day, carrying the streak line. The study day does not
    /// roll over until 04:00, so the true final moment is past midnight — an
    /// hour nobody should be pushed at. 21:30 still leaves an evening to act in.
    private static let lastCallHour = 21
    private static let lastCallMinute = 30

    /// The quiet daytime prompt that names a word.
    private static let nudgeHour = 13
    private static let nudgeMinute = 0

    private static let identifierPrefix = "daily-reminder-"
    private static let wordNudgeIdentifier = "word-nudge-today"

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

    /// A word from today's slot, for the daytime nudge. Injected by
    /// WordOfTheDayManager, which owns the loaded slot.
    var focusWordProvider: (() -> String?)?

    private init() {}

    // MARK: - Permission

    /// Asks for notification permission, after a session has been finished.
    ///
    /// Deliberately not at launch. A cold prompt before anyone has seen what
    /// the app does is the reliable way to be refused, and iOS only allows the
    /// ask once — a refusal can afterwards only be undone in system Settings.
    ///
    /// The only gate is the system status. There used to be a
    /// `dailyReminderDidAskPermission` flag as well, but it was set even on the
    /// paths where no prompt had been shown, and once set nothing looked again:
    /// anyone whose status was still notDetermined at that point could never be
    /// asked. iOS already guarantees the prompt appears at most once per
    /// install, so the flag only ever cost us reach. It is abandoned rather
    /// than migrated — reading it is what did the damage.
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        // The ask happens right after finishing, so today is already done.
        await refreshSchedule(skippingToday: true)
    }

    // MARK: - Scheduling

    /// Rebuilds the pending reminders.
    ///
    /// - Parameter skippingToday: pass true right after a session is finished,
    ///   so the learner is not reminded to do something they already did.
    func refreshSchedule(skippingToday: Bool = false) async {
        clearPending()

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else {
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let streak = streakProvider?() ?? StreakSnapshot()

        for offset in Self.scheduleOffsets {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let fireDate = calendar.date(
                    bySettingHour: Self.lastCallHour,
                    minute: Self.lastCallMinute,
                    second: 0,
                    of: day
                  )
            else { continue }

            // Never schedule in the past — today's slot may already have gone.
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

        // Daytime nudge, TODAY ONLY. Naming one of today's words needs the slot
        // actually loaded, and the word only holds while the slot does —
        // placing it on a later day risks naming a word already moved past.
        // Skipped entirely when no word is available rather than sending a
        // sentence with a hole in it.
        if !skippingToday,
           let word = focusWordProvider?(),
           !word.isEmpty,
           let nudgeDate = calendar.date(
            bySettingHour: Self.nudgeHour, minute: Self.nudgeMinute, second: 0, of: now
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
                hour: Self.nudgeHour,
                minute: Self.nudgeMinute
            )
        }
    }

    /// Re-arms the rolling window. Safe to call on every foreground: it only
    /// rewrites our own requests.
    func refreshOnForeground() async {
        await refreshSchedule()
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
    /// tomorrow's request would read "your 5-day streak" on a morning it is
    /// already zero. Every later step gets its own line instead, so someone
    /// drifting away is not read the same sentence four times.
    private func copy(forDayOffset offset: Int, streak: StreakSnapshot) -> Copy {
        switch offset {
        case 0:
            return Copy(
                title: String(localized: "Today's words are ready"),
                body: todayBody(streak: streak)
            )
        case 1:
            return Copy(
                title: String(localized: "Today's words are ready"),
                body: String(localized: "Yesterday's words are still waiting — a few minutes is all it takes 🙂")
            )
        case 3:
            return Copy(
                title: String(localized: "Still here for you"),
                body: String(localized: "It's been a few days. Picking up where you left off is easier than you think 🌱")
            )
        case 7:
            return Copy(
                title: String(localized: "Still here for you"),
                body: String(localized: "A week away. Even one short quiz is enough to get moving again 💫")
            )
        default:
            return Copy(
                title: String(localized: "Still here for you"),
                body: String(localized: "Your words will be here whenever you're ready 🤍")
            )
        }
    }

    private func todayBody(streak: StreakSnapshot) -> String {
        if streak.current >= 1 {
            return String(
                format: String(localized: "Your %lld-day streak looks great — protect it with a short quiz ✨💪"),
                Int64(streak.current)
            )
        }

        // current == 0 means yesterday was missed. If the day before it was
        // done, the run is still rescuable: finishing today makes yesterday
        // the recoverable gap, which the rewarded video can then bridge.
        if streak.completedDayBeforeYesterday {
            return String(localized: "Finish the short quiz and your streak can still be saved. I believe in you 🥹")
        }

        return streak.best >= 1
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

    private func clearPending() {
        var ids = Self.scheduleOffsets.map { "\(Self.identifierPrefix)\($0)" }
        ids.append(Self.wordNudgeIdentifier)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}
