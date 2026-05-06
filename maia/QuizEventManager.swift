//
//  QuizEventManager.swift
//  maia
//
//  Kelime bazlı quiz sonuçları + bitiş saati (ML için). Firestore: users/{uid}/quizEvents
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

/// Tek quiz denemesi: Kelime X, doğru/yanlış, tarih, saat.
struct QuizEvent: Codable, Identifiable {
    let id: UUID
    let wordId: UUID
    let correct: Int
    let total: Int
    let dateString: String
    let completedAt: Date
    
    init(id: UUID = UUID(), wordId: UUID, correct: Int, total: Int, completedAt: Date = Date()) {
        self.id = id
        self.wordId = wordId
        self.correct = correct
        self.total = total
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        self.dateString = f.string(from: completedAt)
        self.completedAt = completedAt
    }
}

class QuizEventManager: ObservableObject {
    @Published private(set) var events: [QuizEvent] = []
    
    private let eventsKey = "quizEvents"
    private let maxLocalEvents = 1000
    private let db = Firestore.firestore()
    private var lastObservedAuthUID: String?
    
    init() {
        loadLocal()
        lastObservedAuthUID = Auth.auth().currentUser?.uid
        setupAuthListener()
    }

    private func setupAuthListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            let uid = user?.uid
            if uid == self.lastObservedAuthUID { return }
            let previous = self.lastObservedAuthUID
            self.lastObservedAuthUID = uid

            // Events are stored in a global UserDefaults key today.
            if previous != nil || uid == nil {
                self.events = []
                UserDefaults.standard.removeObject(forKey: self.eventsKey)
            }
        }
    }
    
    func record(wordId: UUID, correct: Int, total: Int, completedAt: Date = Date()) {
        let event = QuizEvent(wordId: wordId, correct: correct, total: total, completedAt: completedAt)
        events.insert(event, at: 0)
        if events.count > maxLocalEvents {
            events = Array(events.prefix(maxLocalEvents))
        }
        saveLocal()
        saveToFirestoreIfSignedIn(event: event)
    }
    
    func events(forDate date: Date) -> [QuizEvent] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let target = f.string(from: date)
        return events.filter { $0.dateString == target }
    }
    
    private func loadLocal() {
        guard let data = UserDefaults.standard.data(forKey: eventsKey),
              let decoded = try? JSONDecoder().decode([QuizEvent].self, from: data) else {
            events = []
            return
        }
        events = decoded
    }
    
    private func saveLocal() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: eventsKey)
    }
    
    private func saveToFirestoreIfSignedIn(event: QuizEvent) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(userId).collection("quizEvents").document(event.id.uuidString)
        ref.setData([
            "wordId": event.wordId.uuidString,
            "correct": event.correct,
            "total": event.total,
            "dateString": event.dateString,
            "completedAt": Timestamp(date: event.completedAt)
        ]) { error in
            if let error = error, (error as NSError).code != 7 {
                print("❌ QuizEvent Firestore save error: \(error.localizedDescription)")
            }
        }
    }
}
