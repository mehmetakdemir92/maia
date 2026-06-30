//
//  AppAnalytics.swift
//  maia
//
//  Lightweight analytics pipeline:
//  - Stores events locally for debugging/history
//  - Mirrors events to Firestore when user is signed in
//

import Foundation
import FirebaseAuth
import FirebaseAnalytics
import FirebaseFirestore

struct AppAnalyticsEvent: Identifiable, Codable {
    let id: UUID
    let name: String
    let params: [String: String]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, params: [String: String], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.params = params
        self.createdAt = createdAt
    }
}

enum AppAnalyticsEventName {
    static let appOpen = "app_open"
    static let onboardingStarted = "onboarding_started"
    static let signInStarted = "sign_in_started"
    static let signInCompleted = "sign_in_completed"
    static let signInFailed = "sign_in_failed"
    static let signUpStarted = "sign_up_started"
    static let signUpCompleted = "sign_up_completed"
    static let signUpFailed = "sign_up_failed"
    static let dailyWordViewed = "daily_word_viewed"
    static let quizStarted = "quiz_started"
    static let quizCompleted = "quiz_completed"
    static let paywallViewed = "paywall_viewed"
    static let paywallPlanSelected = "paywall_plan_selected"
    static let paywallCtaTapped = "paywall_cta_tapped"
    static let purchaseStarted = "purchase_started"
    static let purchaseSuccess = "purchase_success"
    static let purchaseFailed = "purchase_failed"
    static let restorePurchaseStarted = "restore_purchase_started"
    static let restorePurchaseSuccess = "restore_purchase_success"
    static let restorePurchaseFailed = "restore_purchase_failed"
    static let adBannerImpression = "ad_banner_impression"
    static let adBannerFailed = "ad_banner_failed"
    static let adInterstitialShown = "ad_interstitial_shown"
    static let adRewardedVideoShown = "ad_rewarded_video_shown"
}

enum AppAnalyticsPlacement {
    static let todayGenerateMore = "today_generate_more"
    static let profileStats = "profile_stats"
    static let settings = "settings"
    static let wordOfDayGenerateMore = "word_of_day_generate_more"
    static let todayBottomBanner = "today_bottom_banner"
    static let todayInlineBannerAfterFirst = "today_inline_banner_after_first"
    static let todayInlineBannerAfterSecond = "today_inline_banner_after_second"
    static let diaryBottomBanner = "diary_bottom_banner"
    static let streakBottomBanner = "streak_bottom_banner"
    static let profileBottomBanner = "profile_bottom_banner"
    static let quizBottomBanner = "quiz_bottom_banner"
    static let quizCompleteInterstitial = "quiz_complete_interstitial"
    static let secondQuizCompleteRewardedVideo = "second_quiz_complete_rewarded_video"
}

final class AppAnalytics {
    static let shared = AppAnalytics()

    private let db = Firestore.firestore()
    private let localEventsKey = "appAnalyticsEvents"
    private let maxLocalEvents = 2000

    private var cachedEvents: [AppAnalyticsEvent] = []
    private var authListener: AuthStateDidChangeListenerHandle?

    private init() {
        loadLocal()
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self, let user else { return }
            self.flushRecentEventsToFirestore(userId: user.uid)
        }
    }

    deinit {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
        }
    }

    func log(_ name: String, params: [String: String] = [:]) {
        var merged = params
        merged["platform"] = "ios"
        merged["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        // Firebase Analytics stream (Dashboard / DebugView).
        Analytics.logEvent(name, parameters: merged)

        let event = AppAnalyticsEvent(name: name, params: merged)
        cachedEvents.insert(event, at: 0)
        if cachedEvents.count > maxLocalEvents {
            cachedEvents = Array(cachedEvents.prefix(maxLocalEvents))
        }
        saveLocal()

        if let userId = Auth.auth().currentUser?.uid {
            saveToFirestore(event: event, userId: userId)
        }
    }

    private func flushRecentEventsToFirestore(userId: String) {
        // Keep flush bounded to avoid large write bursts.
        let recent = cachedEvents.prefix(150)
        for event in recent {
            saveToFirestore(event: event, userId: userId)
        }
    }

    private func saveToFirestore(event: AppAnalyticsEvent, userId: String) {
        let ref = db.collection("users").document(userId).collection("appAnalyticsEvents").document(event.id.uuidString)
        ref.setData([
            "name": event.name,
            "params": event.params,
            "createdAt": Timestamp(date: event.createdAt)
        ], merge: true) { error in
            if let error = error, (error as NSError).code != 7 {
                print("⚠️ AppAnalytics Firestore write error: \(error.localizedDescription)")
            }
        }
    }

    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: localEventsKey),
              let decoded = try? JSONDecoder().decode([AppAnalyticsEvent].self, from: data) else {
            cachedEvents = []
            return
        }
        cachedEvents = decoded
    }

    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(cachedEvents) else { return }
        UserDefaults.standard.set(data, forKey: localEventsKey)
    }
}
