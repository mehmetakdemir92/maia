//
//  WordPronunciationService.swift
//  maia
//
// Cloud TTS (Firebase callable + Storage) → local MP3 cache → iOS TTS fallback.
//

import AVFoundation
import Combine
import FirebaseFunctions
import Foundation

@MainActor
final class WordPronunciationService: NSObject, ObservableObject {
    static let shared = WordPronunciationService()

    @Published private(set) var loadingLemma: String?
    @Published private(set) var speakingLemma: String?

    private let functions = Functions.functions()
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?

    private let urlCachePrefix = "pronunciation.audioURL."

    private override init() {
        super.init()
    }

    /// Prefetch MP3 in background when daily words load (no playback).
    func prefetch(words: [Word]) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for item in words {
                    group.addTask {
                        await self.prefetch(
                            word: item.word,
                            preferredURL: item.pronunciationAudioURL,
                            language: item.learningLanguage
                        )
                    }
                }
            }
        }
    }

    /// Callable + cache; returns URL without playing (enrich / diary sync).
    func resolveAudioURL(for word: String, preferredURL: String? = nil, language: LearningLanguage = .current) async -> String? {
        let lemma = Self.normalizeLemma(word)
        guard !lemma.isEmpty else { return nil }
        if let preferredURL, !preferredURL.isEmpty { return preferredURL }
        if let cached = cachedURL(for: lemma, language: language) { return cached }
        if FileManager.default.fileExists(atPath: localFileURL(for: lemma, language: language).path),
           let cached = cachedURL(for: lemma, language: language) {
            return cached
        }
        guard let fetched = await fetchCloudAudioURL(word: word, language: language) else { return nil }
        publishResolvedURL(fetched, lemma: lemma, language: language)
        if let url = URL(string: fetched) {
            _ = await playRemoteOrCached(url: url, lemma: lemma, language: language, playAudio: false)
        }
        return fetched
    }

    func prefetch(word: String, preferredURL: String? = nil, language: LearningLanguage = .current) async {
        let lemma = Self.normalizeLemma(word)
        guard !lemma.isEmpty else { return }
        if FileManager.default.fileExists(atPath: localFileURL(for: lemma, language: language).path) { return }

        if let urlString = preferredURL ?? cachedURL(for: lemma, language: language),
           let url = URL(string: urlString) {
            _ = await playRemoteOrCached(url: url, lemma: lemma, language: language, playAudio: false)
            return
        }

        if let fetched = await fetchCloudAudioURL(word: word, language: language) {
            publishResolvedURL(fetched, lemma: lemma, language: language)
            if let url = URL(string: fetched) {
                _ = await playRemoteOrCached(url: url, lemma: lemma, language: language, playAudio: false)
            }
        }
    }

    func speak(word: String, preferredURL: String? = nil, language: LearningLanguage = .current) async {
        let lemma = Self.normalizeLemma(word)
        guard !lemma.isEmpty else { return }

        stop()

        if let urlString = preferredURL ?? cachedURL(for: lemma, language: language),
           let url = URL(string: urlString),
           await playRemoteOrCached(url: url, lemma: lemma, language: language, playAudio: true) {
            return
        }

        loadingLemma = lemma
        defer { if loadingLemma == lemma { loadingLemma = nil } }

        if let fetched = await fetchCloudAudioURL(word: word, language: language) {
            publishResolvedURL(fetched, lemma: lemma, language: language)
            if let url = URL(string: fetched),
               await playRemoteOrCached(url: url, lemma: lemma, language: language, playAudio: true) {
                return
            }
        }

        speakWithTTS(word, language: language)
        loadingLemma = nil
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        speakingLemma = nil
    }

    // MARK: - Cloud

    private func fetchCloudAudioURL(word: String, language: LearningLanguage) async -> String? {
        do {
            let result = try await functions.httpsCallable("ensureWordPronunciation")
                .call(["word": word, "language": language.code])
            guard let data = result.data as? [String: Any],
                  let url = data["audioURL"] as? String,
                  !url.isEmpty else {
                return nil
            }
            return url
        } catch {
            print("⚠️ ensureWordPronunciation:", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Playback

    private func playRemoteOrCached(url: URL, lemma: String, language: LearningLanguage, playAudio: Bool) async -> Bool {
        let local = localFileURL(for: lemma, language: language)
        if !FileManager.default.fileExists(atPath: local.path) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try FileManager.default.createDirectory(
                    at: local.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: local, options: .atomic)
            } catch {
                print("⚠️ pronunciation download:", error.localizedDescription)
                return false
            }
        }

        guard playAudio else { return true }
        return playFile(at: local, lemma: lemma)
    }

    private func playFile(at url: URL, lemma: String) -> Bool {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            audioPlayer = player
            speakingLemma = lemma
            player.play()
            return true
        } catch {
            print("⚠️ pronunciation play:", error.localizedDescription)
            return false
        }
    }

    private func publishResolvedURL(_ url: String, lemma: String, language: LearningLanguage) {
        cacheURL(url, for: lemma, language: language)
        NotificationCenter.default.post(
            name: .pronunciationAudioURLResolved,
            object: nil,
            userInfo: ["lemma": lemma, "audioURL": url]
        )
    }

    private func speakWithTTS(_ word: String, language: LearningLanguage) {
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: language.speechVoiceCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        speakingLemma = Self.normalizeLemma(word)
        speechSynthesizer.speak(utterance)
    }

    // MARK: - Cache

    /// English keeps the legacy key/path so existing caches remain valid.
    private func urlCacheKey(for lemma: String, language: LearningLanguage) -> String {
        language == .english
            ? urlCachePrefix + lemma
            : urlCachePrefix + language.code + "." + lemma
    }

    private func cachedURL(for lemma: String, language: LearningLanguage) -> String? {
        UserDefaults.standard.string(forKey: urlCacheKey(for: lemma, language: language))
    }

    private func cacheURL(_ url: String, for lemma: String, language: LearningLanguage) {
        UserDefaults.standard.set(url, forKey: urlCacheKey(for: lemma, language: language))
    }

    private func localFileURL(for lemma: String, language: LearningLanguage) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        var dir = base.appendingPathComponent("pronunciations", isDirectory: true)
        if language != .english {
            dir = dir.appendingPathComponent(language.code, isDirectory: true)
        }
        return dir.appendingPathComponent("\(lemma).mp3", isDirectory: false)
    }

    static func normalizeLemma(_ word: String) -> String {
        let lowered = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "'" {
                return Character(scalar)
            }
            return "_"
        }
        let joined = String(cleaned)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return String(joined.prefix(80))
    }
}

extension WordPronunciationService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if audioPlayer === player {
                audioPlayer = nil
                speakingLemma = nil
            }
        }
    }
}
