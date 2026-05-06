//
//  AppLanguageManager.swift
//  maia
//
//  Uygulama dilini sistemden bağımsız seçmek (Ayarlar → Diller).
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
    /// `localizedString` swizzle: `Bundle.main` için tr.lproj (veya başka .lproj) üzerinden çözüm.
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

    /// `nil` = cihaz dil listesi (sistem varsayılanı). Aksi halde `en` / `tr` gibi ISO kodları.
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

    var id: String { rawValue }

    /// Bundle / AppleLanguages için; sistem = nil
    var languageCode: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .turkish: return "tr"
        }
    }

    var title: String {
        switch self {
        case .system: return String(localized: "System language")
        case .english: return String(localized: "English")
        case .turkish: return String(localized: "Turkish")
        }
    }
}

@MainActor
final class AppLanguageManager: ObservableObject {
    private let storageKey = "appLanguagePreference"

    @Published private(set) var refreshID = UUID()

    var selectedOption: AppLanguageOption {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguageOption.system.rawValue
        return AppLanguageOption(rawValue: raw) ?? .system
    }

    /// Tarih/sayı formatları için (String Catalog’dan ayrı).
    var effectiveLocale: Locale {
        switch selectedOption {
        case .system:
            return Locale.autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .turkish:
            return Locale(identifier: "tr_TR")
        }
    }

    func setSelected(_ option: AppLanguageOption) {
        UserDefaults.standard.set(option.rawValue, forKey: storageKey)
        Self.applyStoredPreference()
        refreshID = UUID()
    }

    static func applyStoredPreference() {
        Bundle.maiaEnsureLocalizationSwizzle()
        let raw = UserDefaults.standard.string(forKey: "appLanguagePreference") ?? AppLanguageOption.system.rawValue
        let option = AppLanguageOption(rawValue: raw) ?? .system
        Bundle.setAppLanguageCode(option.languageCode)
    }
}
