//
//  LearningLanguage.swift
//  maia
//
// Target language the user is studying (daily words, quizzes, TTS, AI help).
// Independent from the app UI language (AppLanguageManager).
//

import Combine
import Foundation

enum LearningLanguage: String, CaseIterable, Identifiable {
    case english
    case german

    nonisolated static let storageKey = "learningLanguagePreference"

    var id: String { rawValue }

    /// ISO 639-1 code used for backend calls, cache namespaces, and `Word.languageCode`.
    nonisolated var code: String {
        switch self {
        case .english: return "en"
        case .german: return "de"
        }
    }

    /// Endonym shown in the picker (fixed, not localized, so users always recognize it).
    var title: String {
        switch self {
        case .english: return "English"
        case .german: return "Deutsch"
        }
    }

    /// English name used inside AI prompts ("Create ONE short, natural German sentence…").
    var promptName: String {
        switch self {
        case .english: return "English"
        case .german: return "German"
        }
    }

    /// AVSpeechSynthesisVoice fallback when cloud TTS is unavailable.
    var speechVoiceCode: String {
        switch self {
        case .english: return "en-US"
        case .german: return "de-DE"
        }
    }

    /// Namespace appended to UserDefaults keys. Empty for English so existing
    /// user data (locked words, used-word history, audio URLs) stays valid.
    var storageSuffix: String {
        switch self {
        case .english: return ""
        case .german: return ".de"
        }
    }

    /// Inflection suffixes accepted when checking that an example sentence
    /// contains the headword (see CurriculumService.exampleIncludesHeadword).
    var headwordSuffixes: [String] {
        switch self {
        case .english:
            return ["s", "es", "ed", "ing", "er", "est", "ly", "d"]
        case .german:
            return ["e", "en", "er", "es", "em", "n", "s", "t", "st", "te", "ten", "tet", "ste", "sten"]
        }
    }

    nonisolated static func fromCode(_ code: String?) -> LearningLanguage {
        guard let code = code?.lowercased(), !code.isEmpty else { return .english }
        return allCases.first { $0.code == code } ?? .english
    }

    /// Currently selected learning language (UserDefaults-backed; defaults to English).
    ///
    /// `nonisolated` on purpose: the project builds with
    /// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so without this every read from
    /// a nonisolated context warns. It only touches UserDefaults, which is
    /// thread-safe, so there is nothing to isolate.
    nonisolated static var current: LearningLanguage {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? LearningLanguage.english.rawValue
        return LearningLanguage(rawValue: raw) ?? .english
    }
}

extension Notification.Name {
    static let learningLanguageChanged = Notification.Name("learningLanguageChanged")
}

@MainActor
final class LearningLanguageManager: ObservableObject {

    @Published private(set) var selected: LearningLanguage

    init() {
        selected = LearningLanguage.current
    }

    func setSelected(_ language: LearningLanguage) {
        guard language != selected else { return }
        UserDefaults.standard.set(language.rawValue, forKey: LearningLanguage.storageKey)
        selected = language
        AppAnalytics.shared.syncUserProperties(learningLanguage: language)
        NotificationCenter.default.post(name: .learningLanguageChanged, object: nil)
    }
}
