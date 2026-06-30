//
//  StreakView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI
import Combine
import GoogleMobileAds

struct StreakView: View {
    @EnvironmentObject var streakManager: StreakManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedMonth = Date()
    @State private var flameScale: CGFloat = 1.0
    @State private var flameOpacity: Double = 0.4
    
    var body: some View {
        NavigationStack {
            ZStack {
                GlassSceneBackground()
                ScrollView {
                    VStack(spacing: 24) {
                        streakHero
                        CalendarView(selectedMonth: $selectedMonth)
                            .environmentObject(streakManager)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var streakHero: some View {
        ZStack {
            Image(systemName: "flame.fill")
                .font(.system(size: 140))
                .foregroundStyle(AppColors.animatedFlameGradient(opacity: flameOpacity))
                .scaleEffect(flameScale)
                .offset(y: -8)
                .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 0)

            VStack(spacing: 4) {
                Text("\(streakManager.currentStreak)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.orange)
                Text("Day Streak")
                    .font(.headline)
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear {
            streakManager.refreshStreak()
            flameScale = 1.0
            flameOpacity = 0.45
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                flameScale = 1.08
                flameOpacity = 0.58
            }
        }
    }
}

/// Use a single LazyVGrid + ForEach with unique ids; separate ForEach(0…6) collides and mis-matches calendar days.
private enum StreakCalendarGridItem: Identifiable, Hashable {
    case weekdayHeader(column: Int, title: String)
    case leadPadding(index: Int)
    case day(dayOfMonth: Int, date: Date)
    case trailPadding(index: Int)

    var id: String {
        switch self {
        case .weekdayHeader(let c, _): return "wh-\(c)"
        case .leadPadding(let i): return "lp-\(i)"
        case .day(let d, _): return "day-\(d)"
        case .trailPadding(let i): return "tp-\(i)"
        }
    }
}

struct CalendarView: View {
    @Binding var selectedMonth: Date
    @EnvironmentObject var streakManager: StreakManager
    @Environment(\.locale) private var locale
    @StateObject private var rewardedAdService = StreakRecoveryRewardedService()
    @State private var adErrorMessage: String?
    @State private var showAdError = false

    private let calendar = Calendar.current

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = locale
        return formatter.string(from: date)
    }
    
    private var days: Int {
        getDaysInMonth(selectedMonth)
    }

    /// First day of the month (start-of-day normalized).
    private var firstDayOfSelectedMonth: Date {
        let components = calendar.dateComponents([.year, .month], from: selectedMonth)
        return calendar.date(from: components) ?? selectedMonth
    }

    /// Column index of the 1st of the selected month (0 = first weekday column).
    private var leadingEmptyDayCount: Int {
        let weekday = calendar.component(.weekday, from: firstDayOfSelectedMonth)
        let firstWeekday = calendar.firstWeekday
        return (weekday - firstWeekday + 7) % 7
    }

    /// Trailing blank cells (0–6) to pad the last row to 7 columns.
    private var trailingEmptyDayCount: Int {
        let used = leadingEmptyDayCount + days
        return (7 - (used % 7)) % 7
    }

    /// Weekday short names starting from locale firstWeekday.
    private var weekdayColumnHeaders: [String] {
        let symbols = calendar.shortWeekdaySymbols
        guard symbols.count == 7 else { return Array(repeating: "–", count: 7) }
        return (0..<7).map { column in
            let weekday = ((calendar.firstWeekday - 1 + column) % 7) + 1
            return symbols[weekday - 1]
        }
    }

    /// Duplicate ForEach ids in LazyVGrid swallow the first week; one list with stable ids is required.
    private var calendarGridItems: [StreakCalendarGridItem] {
        var items: [StreakCalendarGridItem] = []
        for col in 0..<7 {
            items.append(.weekdayHeader(column: col, title: weekdayColumnHeaders[col]))
        }
        for i in 0..<leadingEmptyDayCount {
            items.append(.leadPadding(index: i))
        }
        if days > 0 {
            for d in 1...days {
                items.append(.day(
                    dayOfMonth: d,
                    date: dateFor(dayOffset: d, month: selectedMonth)
                ))
            }
        }
        for i in 0..<trailingEmptyDayCount {
            items.append(.trailPadding(index: i))
        }
        return items
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button(action: {
                    if let newMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) {
                        selectedMonth = newMonth
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(AppColors.primaryButton)
                }
                
                Spacer()
                
                Text(monthTitle(for: selectedMonth))
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppColors.glassCardTitle)
                
                Spacer()
                
                Button(action: {
                    if let newMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) {
                        selectedMonth = newMonth
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(AppColors.primaryButton)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            // Week headers aligned to locale firstWeekday
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(calendarGridItems) { item in
                    switch item {
                    case .weekdayHeader(_, let title):
                        Text(title)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.glassCardMuted)
                            .frame(maxWidth: .infinity)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    case .leadPadding, .trailPadding:
                        StreakCalendarEmptyCell()
                    case .day(let dayOfMonth, let dayDate):
                        StreakDayDotView(
                            date: dayDate,
                            dayOfMonth: dayOfMonth,
                            streakManager: streakManager,
                            showsRecoveryAction: shouldShowRecoveryAction(for: dayDate),
                            recoveryInProgress: rewardedAdService.isLoading,
                            onRecoveryTap: showRecoveryAdIfEligible
                        )
                    }
                }
            }
            .padding(16)

            if streakManager.canRecoverMissedYesterday {
                streakRecoveryCallout
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .wordCardGlassBackground(cornerRadius: 20)
        .padding()
        .alert("Ad Error", isPresented: $showAdError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(adErrorMessage ?? String(localized: "Could not load rewarded ad right now."))
        }
    }

    private var streakRecoveryCallout: some View {
        Button(action: showRecoveryAdIfEligible) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title3)
                    .foregroundColor(AppColors.primaryButton)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Missed yesterday? Watch a short ad to save your streak.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.glassCardTitle)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if rewardedAdService.isLoading {
                    ProgressView()
                        .tint(AppColors.glassCardTitle)
                } else {
                    Text(recoveryButtonLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppColors.primaryButtonGradient)
                        .cornerRadius(8)
                }
            }
            .padding(12)
            .background {
                Group {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                }
                .glassMaterialIgnoresSystemColorScheme()
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .disabled(rewardedAdService.isLoading)
        .accessibilityLabel(
            String(localized: "Missed yesterday? Watch a short ad to save your streak.")
            + ", "
            + recoveryButtonLabel
        )
    }

    private var recoveryButtonLabel: String {
        return String(localized: "Watch ad")
    }
    
    private func getDaysInMonth(_ date: Date) -> Int {
        let range = calendar.range(of: .day, in: .month, for: date)
        return range?.count ?? 0
    }

    private func dateFor(dayOffset: Int, month: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let firstDay = calendar.date(from: components),
              let d = calendar.date(byAdding: .day, value: dayOffset - 1, to: firstDay) else {
            return Date()
        }
        return d
    }

    private func shouldShowRecoveryAction(for dayDate: Date) -> Bool {
        guard let recoverableDate = streakManager.recoverableStreakGapDate() else { return false }
        return calendar.isDate(dayDate, inSameDayAs: recoverableDate)
    }

    private func showRecoveryAdIfEligible() {
        guard streakManager.canRecoverMissedYesterday else { return }
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
                _ = streakManager.recoverYesterdayIfEligible()
            }
        }
    }
}

/// Calendar cell: date + day-of-month (filled = completed, ring = today).
private struct StreakCalendarEmptyCell: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 48)
    }
}

struct StreakDayDotView: View {
    let date: Date
    let dayOfMonth: Int
    @ObservedObject var streakManager: StreakManager
    let showsRecoveryAction: Bool
    let recoveryInProgress: Bool
    let onRecoveryTap: () -> Void
    
    private let calendar = Calendar.current
    
    private var isCompleted: Bool {
        streakManager.isDayCompleted(date)
    }
    
    private var isToday: Bool {
        calendar.isDateInToday(date)
    }
    
    private var isFuture: Bool {
        calendar.compare(date, to: Date(), toGranularity: .day) == .orderedDescending
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .overlay(
                        Circle()
                            .stroke(isToday ? Color.orange : Color.clear, lineWidth: 2)
                    )
                Text("\(dayOfMonth)")
                    .font(.system(size: 15, weight: isToday || isCompleted ? .semibold : .regular))
                    .foregroundColor(textColor)

                if showsRecoveryAction {
                    Button(action: onRecoveryTap) {
                        Image(systemName: recoveryInProgress ? "hourglass" : "video.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red.opacity(0.95), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 14, y: -14)
                    .accessibilityLabel(String(localized: "Recover yesterday streak by watching ad"))
                }
            }
            .frame(width: 48, height: 48)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var textColor: Color {
        if isFuture { return AppColors.glassCardMuted.opacity(0.65) }
        if isCompleted { return .white }
        return AppColors.glassCardTitle
    }
    
    private var fillColor: Color {
        if isFuture { return Color.gray.opacity(0.15) }
        if isCompleted { return Color.orange.opacity(0.9) }
        if isToday { return Color.orange.opacity(0.3) }
        return Color.gray.opacity(0.2)
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
