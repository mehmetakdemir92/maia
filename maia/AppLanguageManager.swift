//
//  AppLanguageManager.swift
//  maia
//
// App language override independent of system locale (Settings → Languages).
//

import Combine
import Foundation
import ObjectiveC
import SwiftUI

private var appLanguageBundleKey: UInt8 = 0

private func appLanguageOverlayBundle() -> Bundle? {
    objc_getAssociatedObject(Bundle.main, &appLanguageBundleKey) as? Bundle
}

extension Bundle {
    /// Swizzles localizedString to resolve via tr.lproj (or other .lproj) on Bundle.main.
    private static let maiaLocalizationSwizzle: Void = {
        let selector = #selector(Bundle.localizedString(forKey:value:table:))
        guard
            let original = class_getInstanceMethod(Bundle.self, selector),
            let swizzled = class_getInstanceMethod(Bundle.self, #selector(Bundle.maia_localizedString(forKey:value:table:)))
        else { return }
        method_exchangeImplementations(original, swizzled)
    }()

    static func maiaEnsureLocalizationSwizzle() {
        _ = maiaLocalizationSwizzle
    }

    @objc func maia_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if self === Bundle.main, let overlay = appLanguageOverlayBundle() {
            let table = tableName ?? "Localizable"
            let s = overlay.localizedString(forKey: key, value: value, table: table)
            if s != key || value != nil {
                return s
            }
        }
        return maia_localizedString(forKey: key, value: value, table: tableName)
    }

    /// nil = device language list (system default); otherwise ISO codes like en / tr.
    static func setAppLanguageCode(_ code: String?) {
        maiaEnsureLocalizationSwizzle()

        objc_setAssociatedObject(Bundle.main, &appLanguageBundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        guard let code = code, !code.isEmpty else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            return
        }

        UserDefaults.standard.set([code], forKey: "AppleLanguages")

        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let langBundle = Bundle(path: path) else {
            return
        }

        objc_setAssociatedObject(
            Bundle.main,
            &appLanguageBundleKey,
            langBundle,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }
}

enum AppLanguageOption: String, CaseIterable, Identifiable {
    case system
    case english
    case turkish
    case german
    case spanish
    case french

    var id: String { rawValue }

    /// For Bundle / AppleLanguages; system = nil
    var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .turkish: return "tr"
        case .german: return "de"
        case .spanish: return "es"
        case .french: return "fr"
        }
    }

    /// Endonym shown in the language picker.
    /// Fixed labels so users can find their language regardless of picker UI locale.
    var title: String {
        switch self {
        case .system: return String(localized: "System language")
        case .english: return "English"
        case .turkish: return "Türkçe"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .french: return "Français"
        }
    }
}

enum ExampleGlossPreference: String, CaseIterable, Identifiable {
    case automatic
    case turkish
    case english
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .turkish: return "Türkçe"
        case .english: return "English"
        case .off: return String(localized: "Off")
        }
    }
}

@MainActor
final class AppLanguageManager: ObservableObject {
    private let storageKey = "appLanguagePreference"
    private let glossPreferenceKey = "exampleGlossPreference"

    @Published private(set) var refreshID = UUID()

    var selectedOption: AppLanguageOption {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguageOption.system.rawValue
        return AppLanguageOption(rawValue: raw) ?? .system
    }

    var exampleGlossPreference: ExampleGlossPreference {
        let raw = UserDefaults.standard.string(forKey: glossPreferenceKey)
            ?? ExampleGlossPreference.automatic.rawValue
        return ExampleGlossPreference(rawValue: raw) ?? .automatic
    }

    /// Date/number formatting (separate from String Catalog).
    var effectiveLocale: Locale {
        switch selectedOption {
        case .system:
            return Locale.autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .turkish:
            return Locale(identifier: "tr_TR")
        case .german:
            return Locale(identifier: "de_DE")
        case .spanish:
            return Locale(identifier: "es_ES")
        case .french:
            return Locale(identifier: "fr_FR")
        }
    }

    /// Preferred language for example-sentence glosses.
    /// Returns `tr`, `en`, or `nil` when glosses are turned off.
    var preferredExampleGlossCode: String? {
        switch exampleGlossPreference {
        case .off:
            return nil
        case .turkish:
            return "tr"
        case .english:
            return "en"
        case .automatic:
            if let code = selectedOption.languageCode {
                if code == "tr" { return "tr" }
                if code == "en" { return "en" }
                // de/es/fr UI: English glosses when available (DE packs).
                return "en"
            }
            let preferred = Locale.preferredLanguages
                .map { String($0.prefix(2)).lowercased() }
            if preferred.contains("tr") { return "tr" }
            return "en"
        }
    }

    func setSelected(_ option: AppLanguageOption) {
        UserDefaults.standard.set(option.rawValue, forKey: storageKey)
        Self.applyStoredPreference()
        refreshID = UUID()
    }

    func setExampleGlossPreference(_ preference: ExampleGlossPreference) {
        UserDefaults.standard.set(preference.rawValue, forKey: glossPreferenceKey)
        refreshID = UUID()
    }

    static func applyStoredPreference() {
        Bundle.maiaEnsureLocalizationSwizzle()
        let raw = UserDefaults.standard.string(forKey: "appLanguagePreference") ?? AppLanguageOption.system.rawValue
        let option = AppLanguageOption(rawValue: raw) ?? .system
        Bundle.setAppLanguageCode(option.languageCode)
    }
}
