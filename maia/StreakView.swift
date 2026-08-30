//
//  StreakView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI
import Combine
import GoogleMobileAds

// MARK: - Shared streak visuals

enum StreakStyle {
    /// Horizontal warm gradient used for completed-day runs in the calendar.
    static let runGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.63, blue: 0.24),
            Color(red: 0.97, green: 0.42, blue: 0.20)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cellHeight: CGFloat = 42
}

struct StreakView: View {
    @EnvironmentObject var streakManager: StreakManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMonth = Date()
    @State private var flamePulse: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.30

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                GlassSceneBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        streakHero
                        statsRow
                        CalendarView(selectedMonth: $selectedMonth)
                            .environmentObject(streakManager)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 48)
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: Hero

    private var streakHero: some View {
        VStack(spacing: 8) {
            ZStack {
                // Soft halo so the flame reads against the blue scene instead of
                // muddying into it the way a low-opacity symbol did.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.orange.opacity(glowOpacity),
                                Color.orange.opacity(0)
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 118
                        )
                    )
                    .frame(width: 236, height: 236)
                    .blur(radius: 10)

                Image(systemName: "flame.fill")
                    .font(.system(size: 116))
                    .foregroundStyle(StreakStyle.runGradient)
                    .scaleEffect(flamePulse)
                    .shadow(color: .orange.opacity(0.45), radius: 16, x: 0, y: 4)

                // Sits in the belly of the flame; white on solid orange instead
                // of orange-on-orange.
                Text("\(streakManager.currentStreak)")
                    .font(.system(size: 50, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
                    .offset(y: 16)
                    .contentTransition(.numericText())
            }
            .frame(height: 178)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text("\(streakManager.currentStreak)") + Text(" ") + Text("Day Streak")
            )

            Text("Day Streak")
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            streakManager.refreshStreak()
            flamePulse = 1.0
            glowOpacity = 0.30
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                flamePulse = 1.05
                glowOpacity = 0.46
            }
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            StreakStatTile(
                icon: "trophy.fill",
                value: "\(streakManager.maxStreak)",
                label: "Best"
            )
            StreakStatTile(
                icon: "checkmark.seal.fill",
                value: "\(streakManager.completedDates.count)",
                label: "Total Days"
            )
            StreakStatTile(
                icon: "calendar",
                value: "\(completedThisMonth)",
                label: "This Month"
            )
        }
    }

    private var completedThisMonth: Int {
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now),
              let firstDay = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now)
              )
        else { return 0 }

        return range.reduce(into: 0) { total, day in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstDay) else {
                return
            }
            if streakManager.isDayCompleted(date) { total += 1 }
        }
    }
}

private struct StreakStatTile: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppColors.primaryButton)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(AppColors.glassCardTitle)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.glassCardMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .statCardGlassBackground(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Calendar

private struct StreakDayCell {
    let dayOfMonth: Int
    let date: Date
}

private struct StreakWeek: Identifiable {
    let id: Int
    let cells: [StreakDayCell?]
}

struct CalendarView: View {
    @Binding var selectedMonth: Date
    @EnvironmentObject var streakManager: StreakManager
    @Environment(\.locale) private var locale
    @StateObject private var rewardedAdService = StreakRecoveryRewardedService()
    @State private var adErrorMessage: String?
    @State private var showAdError = false

    private let calendar = Calendar.current

    var body: some View {
        let bridgeDates = streakManager.bridgeableGapDates()

        return VStack(spacing: 14) {
            monthHeader
            weekdayHeaderRow

            VStack(spacing: 6) {
                ForEach(weeks) { week in
                    StreakWeekRow(
                        week: week,
                        isCompleted: streakManager.isDayCompleted,
                        isToday: { calendar.isDateInToday($0) },
                        isFuture: isFuture,
                        isBridgeGap: { date in
                            bridgeDates.contains { calendar.isDate($0, inSameDayAs: date) }
                        }
                    )
                }
            }

            if !bridgeDates.isEmpty {
                streakBridgeCallout(gapLength: bridgeDates.count)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .wordCardGlassBackground(cornerRadius: 24)
        .alert("Ad Error", isPresented: $showAdError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(adErrorMessage ?? String(localized: "Could not load rewarded ad right now."))
        }
    }

    // MARK: Header

    private var monthHeader: some View {
        HStack(spacing: 8) {
            monthStepButton(systemName: "chevron.left", enabled: true) {
                step(by: -1)
            }

            Spacer(minLength: 0)

            Text(monthTitle(for: selectedMonth))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(AppColors.glassCardTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            monthStepButton(systemName: "chevron.right", enabled: canGoToNextMonth) {
                step(by: 1)
            }
        }
    }

    private func monthStepButton(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote.weight(.bold))
                .foregroundColor(
                    enabled ? AppColors.primaryButton : AppColors.glassCardMuted.opacity(0.32)
                )
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(Color.black.opacity(enabled ? 0.06 : 0.03))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var weekdayHeaderRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdayColumnHeaders.enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundColor(AppColors.glassCardMuted.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func step(by months: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: months, to: selectedMonth)
        else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedMonth = newMonth
        }
    }

    /// Paging past the current month only ever shows empty cells, so the
    /// forward chevron stops there.
    private var canGoToNextMonth: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: selectedMonth)
        else { return false }
        return calendar.compare(next, to: Date(), toGranularity: .month) != .orderedDescending
    }

    // MARK: Recovery

    /// Shown only when a real bridge exists: a 1–3 day gap with a completed
    /// streak on both sides.
    private func streakBridgeCallout(gapLength: Int) -> some View {
        Button(action: showBridgeAdIfEligible) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.left.and.right")
                    .font(.footnote.weight(.bold))
                    .foregroundColor(.white)
                    .padding(7)
                    .background(StreakStyle.runGradient, in: Circle())

                Text(bridgePrompt(gapLength: gapLength))
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(AppColors.glassCardTitle)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if rewardedAdService.isLoading {
                    ProgressView()
                        .tint(AppColors.glassCardTitle)
                } else {
                    Text(recoveryButtonLabel)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(StreakStyle.runGradient, in: Capsule())
                        .fixedSize()
                }
            }
            .padding(12)
            .background {
                Group {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                }
                .glassMaterialIgnoresSystemColorScheme()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(rewardedAdService.isLoading)
        .accessibilityLabel(bridgePrompt(gapLength: gapLength) + ", " + recoveryButtonLabel)
    }

    private func bridgePrompt(gapLength: Int) -> String {
        String(
            localized: "Watch a short ad to fill this \(gapLength)-day gap and reconnect your streak."
        )
    }

    private var recoveryButtonLabel: String {
        return String(localized: "Watch ad")
    }

    // MARK: Month math

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = locale
        return formatter.string(from: date)
    }

    private var days: Int {
        calendar.range(of: .day, in: .month, for: selectedMonth)?.count ?? 0
    }

    private var firstDayOfSelectedMonth: Date {
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        return calendar.date(from: components) ?? selectedMonth
    }

    /// Column index of the 1st of the selected month (0 = first weekday column).
    private var leadingEmptyDayCount: Int {
        let weekday = calendar.component(.weekday, from: firstDayOfSelectedMonth)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// Weekday short names starting from locale firstWeekday.
    private var weekdayColumnHeaders: [String] {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: "-", count: 7) }
        return (0..<7).map { column in
            let weekday = ((calendar.firstWeekday - 1 + column) % 7) + 1
            return symbols[weekday - 1]
        }
    }

    /// Rows of 7, padded at both ends — a run of completed days can then be
    /// drawn as one connected bar per row.
    private var weeks: [StreakWeek] {
        var cells: [StreakDayCell?] = Array(repeating: nil, count: leadingEmptyDayCount)
        if days > 0 {
            for day in 1...days {
                cells.append(
                    StreakDayCell(dayOfMonth: day, date: dateFor(dayOffset: day))
                )
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).enumerated().map { index, start in
            StreakWeek(id: index, cells: Array(cells[start..<(start + 7)]))
        }
    }

    /// Cells are anchored at midday, not midnight. The study day starts at
    /// `CurriculumStateManager.dayResetHour` (04:00), so a midnight instant
    /// resolves to the *previous* study day and every cell would read its
    /// neighbour's completion state.
    private func dateFor(dayOffset: Int) -> Date {
        let midnight = calendar.date(
            byAdding: .day, value: dayOffset - 1, to: firstDayOfSelectedMonth
        ) ?? firstDayOfSelectedMonth
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: midnight) ?? midnight
    }

    private func isFuture(_ date: Date) -> Bool {
        calendar.compare(date, to: Date(), toGranularity: .day) == .orderedDescending
    }

    private func showBridgeAdIfEligible() {
        guard streakManager.canBridgeStreakGap else { return }
        presentRecoveryAd()
    }

    private func presentRecoveryAd() {
        rewardedAdService.presentRecoverAd { didEarnReward, error in
            if let error {
                adErrorMessage = error.localizedDescription
                showAdError = true
                return
            }
            if didEarnReward {
                _ = streakManager.bridgeStreakGapIfEligible()
            }
        }
    }
}

// MARK: - Week row

/// One calendar week. Consecutive completed days in the row are drawn as a
/// single connected bar so a streak reads as a run rather than loose dots.
private struct StreakWeekRow: View {
    let week: StreakWeek
    let isCompleted: (Date) -> Bool
    let isToday: (Date) -> Bool
    let isFuture: (Date) -> Bool
    let isBridgeGap: (Date) -> Bool

    private var height: CGFloat { StreakStyle.cellHeight }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    runSegment(at: column)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { column in
                    dayLabel(at: column)
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
        }
    }

    private func completed(_ column: Int) -> Bool {
        guard column >= 0, column < 7, let cell = week.cells[column] else { return false }
        return isCompleted(cell.date)
    }

    @ViewBuilder
    private func runSegment(at column: Int) -> some View {
        if completed(column) {
            let joinsLeft = completed(column - 1)
            let joinsRight = completed(column + 1)
            let radius = height / 2

            UnevenRoundedRectangle(
                topLeadingRadius: joinsLeft ? 0 : radius,
                bottomLeadingRadius: joinsLeft ? 0 : radius,
                bottomTrailingRadius: joinsRight ? 0 : radius,
                topTrailingRadius: joinsRight ? 0 : radius,
                style: .continuous
            )
            .fill(StreakStyle.runGradient)
            .shadow(color: .orange.opacity(0.30), radius: 5, x: 0, y: 2)
            .padding(.leading, joinsLeft ? 0 : 3)
            .padding(.trailing, joinsRight ? 0 : 3)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func dayLabel(at column: Int) -> some View {
        if let cell = week.cells[column] {
            let done = isCompleted(cell.date)
            let today = isToday(cell.date)
            let future = isFuture(cell.date)
            let markerSize = height - 6

            ZStack {
                // No disc behind plain days — bare numerals are what let the
                // orange run read as the only marked thing on the grid.
                if isBridgeGap(cell.date) {
                    Circle()
                        .strokeBorder(
                            Color.orange.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.6, dash: [3.5, 3])
                        )
                        .frame(width: markerSize, height: markerSize)
                }

                if today {
                    Circle()
                        .strokeBorder(
                            done ? Color.white.opacity(0.95) : AppColors.primaryButton,
                            lineWidth: 2
                        )
                        .frame(width: markerSize, height: markerSize)
                }

                Text("\(cell.dayOfMonth)")
                    .font(.system(size: 14, weight: done || today ? .bold : .medium, design: .rounded))
                    .foregroundColor(textColor(done: done, future: future))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: cell, done: done, today: today))
        } else {
            Color.clear
        }
    }

    private func textColor(done: Bool, future: Bool) -> Color {
        if done { return .white }
        if future { return AppColors.glassCardMuted.opacity(0.35) }
        return AppColors.glassCardBody.opacity(0.72)
    }

    private func accessibilityLabel(
        for cell: StreakDayCell,
        done: Bool,
        today: Bool
    ) -> String {
        var parts = ["\(cell.dayOfMonth)"]
        if today { parts.append(String(localized: "Today")) }
        parts.append(
            done
            ? String(localized: "Completed")
            : String(localized: "Not completed")
        )
        return parts.joined(separator: ", ")
    }
}

final class StreakRecoveryRewardedService: NSObject, ObservableObject, GADFullScreenContentDelegate {
    @Published var isLoading = false

    private var rewardedAd: GADRewardedAd?
    private var rewardedInterstitialAd: GADRewardedInterstitialAd?
    private var didEarnReward = false
    private var completion: ((Bool, Error?) -> Void)?

    func presentRecoverAd(completion: @escaping (Bool, Error?) -> Void) {
        guard !isLoading else { return }
        self.completion = completion
        self.isLoading = true
        self.didEarnReward = false

        GADRewardedInterstitialAd.load(withAdUnitID: AdMobConfig.rewardedInterstitialAdUnitID, request: GADRequest()) { [weak self] interstitialAd, interstitialError in
            guard let self else { return }
            if let interstitialAd {
                self.isLoading = false
                self.rewardedInterstitialAd = interstitialAd
                interstitialAd.fullScreenContentDelegate = self
                guard let rootVC = Self.topViewController() else {
                    completion(false, NSError(domain: "StreakRecoveryRewardedService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not present ad."]))
                    return
                }
                interstitialAd.present(fromRootViewController: rootVC) { [weak self] in
                    self?.didEarnReward = true
                }
                return
            }

            GADRewardedAd.load(withAdUnitID: AdMobConfig.rewardedAdUnitID, request: GADRequest()) { [weak self] rewardedAd, rewardedError in
                guard let self else { return }
                self.isLoading = false

                if let rewardedAd {
                    self.rewardedAd = rewardedAd
                    rewardedAd.fullScreenContentDelegate = self
                    guard let rootVC = Self.topViewController() else {
                        completion(false, NSError(domain: "StreakRecoveryRewardedService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Could not present ad."]))
                        return
                    }
                    rewardedAd.present(fromRootViewController: rootVC) { [weak self] in
                        self?.didEarnReward = true
                    }
                    return
                }

                completion(
                    false,
                    rewardedError ?? interstitialError ?? NSError(
                        domain: "StreakRecoveryRewardedService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Rewarded ad unavailable."]
                    )
                )
            }
        }
    }

    func adDidDismissFullScreenContent(_ ad: any GADFullScreenPresentingAd) {
        if didEarnReward {
            completion?(true, nil)
        } else {
            let error = NSError(
                domain: "StreakRecoveryRewardedService",
                code: -3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Please watch the ad to recover streak."
                ]
            )
            completion?(false, error)
        }
        completion = nil
        rewardedAd = nil
        rewardedInterstitialAd = nil
    }

    func ad(_ ad: any GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        completion?(false, error)
        completion = nil
        rewardedAd = nil
        rewardedInterstitialAd = nil
    }

    private static func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first { $0.isKeyWindow }?.rootViewController
    }
}

#Preview {
    StreakView()
        .environmentObject(StreakManager())
}
