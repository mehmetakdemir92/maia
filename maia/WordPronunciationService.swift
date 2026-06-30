//
//  WordPronunciationService.swift
//  maia
//
//  Bulut TTS (Firebase callable + Storage) → yerel MP3 önbellek → yoksa iOS TTS.
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

    /// Günün kelimeleri yüklendiğinde arka planda MP3 indir (çalmadan).
    func prefetch(words: [Word]) {
        Task {
            await withTaskGroup(of: Void.self) { group in
                for item in words {
                    group.addTask {
                        await self.prefetch(word: item.word, preferredURL: item.pronunciationAudioURL)
                    }
                }
            }
        }
    }

    /// Callable + önbellek; çalmadan URL döner (enrich / diary senkronu için).
    func resolveAudioURL(for word: String, preferredURL: String? = nil) async -> String? {
        let lemma = Self.normalizeLemma(word)
        guard !lemma.isEmpty else { return nil }
        if let preferredURL, !preferredURL.isEmpty { return preferredURL }
        if let cached = cachedURL(for: lemma) { return cached }
        if FileManager.default.fileExists(atPath: localFileURL(for: lemma).path),
           let cached = cachedURL(for: lemma) {
            return cached
        }
        guard let fetched = await fetchCloudAudioURL(word: word) else { return nil }
        publishResolvedURL(fetched, lemma: lemma)
        if let url = URL(string: fetched) {
            _ = await playRemoteOrCached(url: url, lemma: lemma, playAudio: false)
        }
        return fetched
    }

    func prefetch(word: String, preferredURL: String? = nil) async {
        let lemma = Self.normalizeLemma(word)
        guard !lemma.isEmpty else { return }
        if FileManager.default.fileExists(atPath: localFileURL(for: lemma).path) { return }

        if let urlString = preferredURL ?? cachedURL(for: lemma),
           let url = URL(string: urlString) {
            _ = await playRemoteOrCached(url: url, lemma: lemma, playAudio: false)
            return
        }

        if let fetched = await fetchCloudAudioURL(word: word) {
            publishResolvedURL(fetched, lemma: lemma)
            if let url = URL(string: fetched) {
                _ = await playRemoteOrCached(url: url, lemma: lemma, playAudio: false)
            }
        }
    }

    func speak(word: String, preferredURL: String? = nil) async {
        let lemma = Self.normalizeLemma(word)
        guard !lemma.isEmpty else { return }

        stop()

        if let urlString = preferredURL ?? cachedURL(for: lemma),
           let url = URL(string: urlString),
           await playRemoteOrCached(url: url, lemma: lemma, playAudio: true) {
            return
        }

        loadingLemma = lemma
        defer { if loadingLemma == lemma { loadingLemma = nil } }

        if let fetched = await fetchCloudAudioURL(word: word) {
            publishResolvedURL(fetched, lemma: lemma)
            if let url = URL(string: fetched),
               await playRemoteOrCached(url: url, lemma: lemma, playAudio: true) {
                return
            }
        }

        speakWithTTS(word)
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

    private func fetchCloudAudioURL(word: String) async -> String? {
        do {
            let result = try await functions.httpsCallable("ensureWordPronunciation").call(["word": word])
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

    private func playRemoteOrCached(url: URL, lemma: String, playAudio: Bool) async -> Bool {
        let local = localFileURL(for: lemma)
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

    private func publishResolvedURL(_ url: String, lemma: String) {
        cacheURL(url, for: lemma)
        NotificationCenter.default.post(
            name: .pronunciationAudioURLResolved,
            object: nil,
            userInfo: ["lemma": lemma, "audioURL": url]
        )
    }

    private func speakWithTTS(_ word: String) {
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        speakingLemma = Self.normalizeLemma(word)
        speechSynthesizer.speak(utterance)
    }

    // MARK: - Cache

    private func cachedURL(for lemma: String) -> String? {
        UserDefaults.standard.string(forKey: urlCachePrefix + lemma)
    }

    private func cacheURL(_ url: String, for lemma: String) {
        UserDefaults.standard.set(url, forKey: urlCachePrefix + lemma)
    }

    private func localFileURL(for lemma: String) -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("pronunciations", isDirectory: true)
            .appendingPathComponent("\(lemma).mp3", isDirectory: false)
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
