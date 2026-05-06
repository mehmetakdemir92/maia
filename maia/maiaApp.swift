//
//  maiaApp.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import GoogleMobileAds

@main
struct maiaApp: App {
    @StateObject private var languageManager = AppLanguageManager()

    init() {
        Bundle.maiaEnsureLocalizationSwizzle()
        FirebaseApp.configure()
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        AppLanguageManager.applyStoredPreference()
        AppAnalytics.shared.log(AppAnalyticsEventName.appOpen)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
