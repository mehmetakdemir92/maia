//
//  AppUpdateChecker.swift
//  maia
//
// Compares the installed version against the App Store (iTunes lookup)
// and prompts at most once per day while an update is pending.
//

import Combine
import Foundation
import UIKit

@MainActor
final class AppUpdateChecker: ObservableObject {
    @Published var updateAvailable = false

    /// Opens the native App Store app. `https://apps.apple.com/...` often lands in Safari.
    static let appStoreURL = URL(string: "itms-apps://itunes.apple.com/app/id6763566092")!
    private static let appStoreWebFallbackURL = URL(string: "https://apps.apple.com/app/id6763566092")!
    private static let lookupURL = URL(string: "https://itunes.apple.com/lookup?bundleId=com.mehmetakdemir.maia&country=tr")!
    private static let lastPromptDayKey = "appUpdate.lastPromptDay"

    func checkOnLaunch() async {
        #if DEBUG
        // Quiz/word content ships in the app bundle — App Store update won't apply local JSON edits.
        return
        #endif
        guard Self.canPromptToday() else { return }
        guard let storeVersion = await Self.fetchStoreVersion() else { return }

        let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        if Self.isVersion(storeVersion, newerThan: installed) {
            updateAvailable = true
        }
    }

    /// Call when the user dismisses the update alert (Later or Update Now).
    static func recordPromptDismissed(now: Date = Date()) {
        UserDefaults.standard.set(dayString(for: now), forKey: lastPromptDayKey)
    }

    static func openAppStore() {
        UIApplication.shared.open(appStoreURL, options: [:]) { opened in
            guard !opened else { return }
            Task { @MainActor in
                UIApplication.shared.open(appStoreWebFallbackURL)
            }
        }
    }

    /// Numeric per-component comparison ("1.1.10" > "1.1.9", "1.2" > "1.1.9").
    static func isVersion(_ candidate: String, newerThan installed: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Internals

    private static func fetchStoreVersion() async -> String? {
        var request = URLRequest(url: lookupURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let version = results.first?["version"] as? String
        else { return nil }
        return version
    }

    private static func canPromptToday(now: Date = Date()) -> Bool {
        UserDefaults.standard.string(forKey: lastPromptDayKey) != dayString(for: now)
    }

    private static func dayString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
