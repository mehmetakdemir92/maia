//
//  CoachDemoView.swift
//  maia
//
//  Day-1 DEBUG screen: prove Gemini (or mock) tokens stream into UI.
//

import SwiftUI

struct CoachDemoView: View {
    @State private var baseURLString = "http://127.0.0.1:8787"
    @State private var sentence = "i go to school yesterday and learn new word"
    @State private var word = "yesterday"
    @State private var streamed = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                TextField("Base URL", text: $baseURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Word (optional)", text: $word)
                TextField("Sentence", text: $sentence, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Request")
            } footer: {
                Text("Simulator → 127.0.0.1. Device → your Mac LAN IP. Run backend-coach with npm run dev.")
            }

            Section("Stream") {
                if streamed.isEmpty && !isStreaming {
                    Text("Tap Stream — tokens should appear gradually.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(streamed)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            Section {
                Button {
                    startStream()
                } label: {
                    HStack {
                        if isStreaming { ProgressView() }
                        Text(isStreaming ? "Streaming…" : "Stream coach reply")
                    }
                }
                .disabled(isStreaming || sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if isStreaming {
                    Button("Cancel", role: .destructive) {
                        streamTask?.cancel()
                        streamTask = nil
                        isStreaming = false
                    }
                }

                Button("Clear") {
                    streamed = ""
                    errorMessage = nil
                }
                .disabled(isStreaming)
            }
        }
        .navigationTitle("Coach stream")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            streamTask?.cancel()
        }
    }

    private func startStream() {
        errorMessage = nil
        streamed = ""
        isStreaming = true

        guard let baseURL = URL(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = "Invalid base URL"
            isStreaming = false
            return
        }

        let client = CoachStreamClient(baseURL: baseURL)
        let sentence = self.sentence
        let word = self.word.trimmingCharacters(in: .whitespacesAndNewlines)

        streamTask = Task { @MainActor in
            defer {
                isStreaming = false
                streamTask = nil
            }
            do {
                let stream = client.streamCoach(
                    sentence: sentence,
                    word: word.isEmpty ? nil : word,
                    skipAuth: true
                )
                for try await delta in stream {
                    streamed += delta
                }
            } catch is CancellationError {
                // user cancelled
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        CoachDemoView()
    }
}
