//
//  ExampleGenerator.swift
//  maia
//
//  Created by Mehmet Akdemir on 25.01.2026.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore


final class ExampleGenerator {

    // Cloud Run Gemini backend (Today “generate example” ile aynı)
    private let baseURL =
        URL(string: "https://gemini-backend-359781552395.europe-west4.run.app")!
    
    init() {}

    /// Gemini (Cloud Run) ile 1 örnek cümle üretir.
    /// - `avoidingSentences`: Havuz / önceki AI cümleleri; modele açıkça verilir (yalnızca prompt’ta “farklı ol” demek yetmez).
    /// - `useAlternateModel`: İkinci “Generate more” için backend’de `GEMINI_ALT_MODEL` (ör. Pro) — Flash ile aynı tekrar eğilimini kırar.
    func generateExample(
        for word: Word,
        avoidingSentences: [String],
        useAlternateModel: Bool = false
    ) async throws -> String {
        let avoid = avoidingSentences
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let avoidBlock: String
        if avoid.isEmpty {
            avoidBlock = ""
        } else {
            let lines = avoid.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            let bannedOpenings = Self.distinctFirstTwoWordPrefixes(from: avoid)
            let openingsLine = bannedOpenings.isEmpty
                ? ""
                : """

            Banned openings (your new sentence must NOT begin with these two words in this order, case-insensitive): \(bannedOpenings.joined(separator: "; "))
            """
            avoidBlock = """

            Existing example sentence(s) — do NOT imitate structure, setting, or cast of characters; avoid paraphrase and synonym swaps only. Invent a clearly different scenario (e.g. if (1) is work/school, use travel, home, nature, or a different social context):

            \(lines)\(openingsLine)

            Syntactic variety (mandatory): use a different sentence “shape” than the lines above — e.g. if they are first-person statements, prefer third person, a question, a subordinate clause, passive, or there-construction; do not chain the same subject + main-verb frame (e.g. two sentences both starting "I estimate …").
            """
        }

        let prompt = """
        Create ONE short, natural English sentence using the exact word "\(word.word)".

        Meaning (for context):
        \(word.definition)
        \(avoidBlock)

        Rules:
        - Output ONLY the sentence (no quotes, no explanation).
        - 8–14 words.
        - The sentence must feel fresh compared to any listed existing examples.

        """
        return try await postGenerate(prompt: prompt, useAlternateModel: useAlternateModel)
    }

    /// İlk iki kelime tekrarını (ör. "I estimate …" / "I estimate …") modele yasak listesi olarak verir.
    private static func distinctFirstTwoWordPrefixes(from sentences: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in sentences {
            let parts = s.split { $0.isWhitespace || $0.isNewline }.map(String.init)
            guard parts.count >= 2 else { continue }
            let w1 = parts[0].trimmingCharacters(in: .init(charactersIn: "“”\"'‘’"))
            let w2 = parts[1].trimmingCharacters(in: .init(charactersIn: "“”\"'‘’"))
            guard !w1.isEmpty, !w2.isEmpty else { continue }
            let key = "\(w1) \(w2)".lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                out.append("\"\(w1) \(w2)\"")
            }
        }
        return out
    }

    /// Diary’deki örnek cümle: ana sayfadaki ile aynı backend (`/generate`), minimal düzeltme + doğal kelime kullanımı.
    func suggestDiarySentenceImprovement(for word: Word, userSentence: String) async throws -> String {
        let trimmed = userSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "ExampleGenerator", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Empty sentence"])
        }

        let prompt = """
        The student wrote a sentence using the word "\(word.word)".

        Word meaning (context):
        \(word.definition)

        Student's sentence:
        \(trimmed)

        Improve this sentence with MINIMAL changes only: fix grammar and spelling where needed; choose natural, efficient English where a small wording change clearly helps. Keep the same meaning and intent; do not replace it with a completely different idea or a brand-new sentence from scratch.

        Reply with ONLY the improved single sentence. No quotes, no explanation, no markdown.
        """

        return try await postGenerate(prompt: prompt, useAlternateModel: false)
    }

    // MARK: - Private

    private func postGenerate(prompt: String, useAlternateModel: Bool = false) async throws -> String {
        let token = try await fetchIDToken()

        // Vertex/Gemini can return 429 under bursty taps; retry with backoff instead of failing immediately.
        let maxAttempts = 4
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            var request = URLRequest(url: baseURL.appendingPathComponent("generate"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            var body: [String: Any] = ["prompt": prompt]
            if useAlternateModel {
                body["use_alternate_model"] = true
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let msg = String(data: data, encoding: .utf8) ?? ""
                    if http.statusCode == 429, attempt < maxAttempts - 1 {
                        let delayMs = UInt64(450) * UInt64(1 << attempt) // 450ms, 900ms, 1800ms...
                        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                        continue
                    }
                    throw NSError(
                        domain: "ExampleGenerator",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: friendlyBackendError(status: http.statusCode, body: msg)]
                    )
                }

                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let text = (obj?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                if text.isEmpty {
                    throw NSError(domain: "ExampleGenerator", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Empty response from backend"])
                }

                return text
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    let delayMs = UInt64(450) * UInt64(1 << attempt)
                    try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? NSError(
            domain: "ExampleGenerator",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Couldn’t reach the example generator. Please try again."]
        )
    }

    private func friendlyBackendError(status: Int, body: String) -> String {
        let lower = body.lowercased()
        if status == 429 || lower.contains("rate exceeded") || lower.contains("resource exhausted") {
            return String(localized: "The AI service is busy right now. Please wait a few seconds and try again.")
        }
        if (500...599).contains(status) {
            return String(localized: "The AI service is temporarily unavailable. Please try again in a moment.")
        }
        return String(localized: "Couldn’t generate an example right now. Please try again.")
    }

    private func fetchIDToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "Auth", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "User not signed in"])
        }

        return try await withCheckedThrowingContinuation { cont in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: token ?? "")
                }
            }
        }
    }
}
