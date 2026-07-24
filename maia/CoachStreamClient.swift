//
//  CoachStreamClient.swift
//  maia
//
//  Day-1: consumes SSE from backend-coach /coach/stream
//

import Foundation
import FirebaseAuth

enum CoachStreamError: LocalizedError {
    case notSignedIn
    case badURL
    case httpStatus(Int, String)
    case server(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in required."
        case .badURL: return "Invalid coach base URL."
        case .httpStatus(let code, let body): return "HTTP \(code): \(body)"
        case .server(let msg): return msg
        case .empty: return "Empty stream."
        }
    }
}

struct CoachStreamChunk: Decodable {
    var text: String?
    var done: Bool?
    var error: String?
    var event: String?
    var mock: Bool?
}

/// Streams coach tokens via Server-Sent Events.
final class CoachStreamClient {
    var baseURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Yields text deltas as they arrive. Throws on hard failure.
    func streamCoach(
        sentence: String,
        word: String? = nil,
        definition: String? = nil,
        skipAuth: Bool = true
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.performStream(
                        sentence: sentence,
                        word: word,
                        definition: definition,
                        skipAuth: skipAuth,
                        onText: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func performStream(
        sentence: String,
        word: String?,
        definition: String?,
        skipAuth: Bool,
        onText: @escaping (String) -> Void
    ) async throws {
        guard let url = URL(string: "coach/stream", relativeTo: baseURL)?.absoluteURL else {
            throw CoachStreamError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120

        if !skipAuth {
            let token = try await fetchIDToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body: [String: Any] = ["sentence": sentence]
        if let word, !word.isEmpty { body["word"] = word }
        if let definition, !definition.isEmpty { body["definition"] = definition }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var data = Data()
            for try await b in bytes { data.append(b) }
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw CoachStreamError.httpStatus(http.statusCode, msg)
        }

        var sawText = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]" else { continue }

            guard let data = payload.data(using: .utf8) else { continue }
            let chunk = try JSONDecoder().decode(CoachStreamChunk.self, from: data)
            if let err = chunk.error, !err.isEmpty {
                throw CoachStreamError.server(err)
            }
            if let text = chunk.text, !text.isEmpty {
                sawText = true
                onText(text)
            }
            if chunk.done == true { break }
        }

        if !sawText {
            throw CoachStreamError.empty
        }
    }

    private func fetchIDToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw CoachStreamError.notSignedIn
        }
        return try await withCheckedThrowingContinuation { cont in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: token ?? "") }
            }
        }
    }
}
