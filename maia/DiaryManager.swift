//
//  DiaryManager.swift
//  maia
//
//  Created by Mehmet Akdemir on 22.01.2026.
//

import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    /// "Use this example" ile öneri uygulandıysa true; Suggestion butonu bir daha gösterilmez.
    var suggestionApplyUsed: Bool
    
    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), suggestionApplyUsed: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.suggestionApplyUsed = suggestionApplyUsed
    }
    
    enum CodingKeys: String, CodingKey {
        case id, text, createdAt, suggestionApplyUsed
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        suggestionApplyUsed = try c.decodeIfPresent(Bool.self, forKey: .suggestionApplyUsed) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(suggestionApplyUsed, forKey: .suggestionApplyUsed)
    }
}

struct DiaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    var words: [Word]
    var notesByWordId: [UUID: [Note]] // wordId -> notes array
    
    init(id: UUID = UUID(), date: Date, words: [Word] = [], notesByWordId: [UUID: [Note]] = [:]) {
        self.id = id
        self.date = date
        self.words = words
        self.notesByWordId = notesByWordId
    }
}

class DiaryManager: ObservableObject {
    @Published var entries: [DiaryEntry] = []

    /// Firestore dinleyicisi hata verdiğinde kullanıcıya; başarılı senkron veya `clearCloudSyncUserMessage()` ile temizlenir.
    @Published private(set) var cloudSyncUserMessage: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var lastObservedAuthUID: String?

    private static let legacyDiaryEntriesKey = "diaryEntries"

    private func diaryStorageKey(forUserId uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return "diaryEntries.\(uid)"
    }
    
    init() {
        loadDiaryEntries()
        lastObservedAuthUID = Auth.auth().currentUser?.uid
        setupAuthListener()
    }
    
    deinit {
        listener?.remove()
    }
    
    private func setupAuthListener() {
        // Auth state değiştiğinde sync yap
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            let uid = user?.uid
            if uid == self.lastObservedAuthUID { return }
            let previous = self.lastObservedAuthUID
            self.lastObservedAuthUID = uid

            if let uid {
                // Account switch: local diary is global today; clear before attaching the new user's listener.
                if previous != nil {
                    self.cloudSyncUserMessage = nil
                    self.entries = []
                    if let prevUserId = previous,
                       let oldKey = self.diaryStorageKey(forUserId: prevUserId) {
                        UserDefaults.standard.removeObject(forKey: oldKey)
                    }
                    UserDefaults.standard.removeObject(forKey: Self.legacyDiaryEntriesKey)
                } else {
                    self.loadDiaryEntries()
                }
                self.syncFromFirestore(userId: uid)
            } else {
                // Çıkış yapıldı - listener'ı kaldır
                self.cloudSyncUserMessage = nil
                self.listener?.remove()
                self.listener = nil
                self.entries = []
                if let prevUserId = previous,
                   let oldKey = self.diaryStorageKey(forUserId: prevUserId) {
                    UserDefaults.standard.removeObject(forKey: oldKey)
                }
                UserDefaults.standard.removeObject(forKey: Self.legacyDiaryEntriesKey)
            }
        }
    }
    
    private func syncLocalToFirestore(userId: String) {
        // Local'deki tüm entries'i Firestore'a gönder
        for entry in entries {
            createOrUpdateEntryInFirestore(entry: entry, userId: userId)
        }
    }
    
    func clearCloudSyncUserMessage() {
        cloudSyncUserMessage = nil
    }

    func resetDiaryDataForDebug() {
        entries = []
        if let uid = Auth.auth().currentUser?.uid,
           let key = diaryStorageKey(forUserId: uid) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyDiaryEntriesKey)
        print("✅ Diary data reset - all entries cleared")
    }
    
    func getOrCreateEntry(for date: Date) -> DiaryEntry {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        // Check if entry exists
        if let existingEntry = entries.first(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            return existingEntry
        }
        
        // Create new entry
        let newEntry = DiaryEntry(date: targetDate, words: [])
        entries.append(newEntry)
        saveDiaryEntries()
        return newEntry
    }
    
    func getEntry(for date: Date) -> DiaryEntry? {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        return entries.first(where: { calendar.isDate($0.date, inSameDayAs: targetDate) })
    }
    
    func markWordAsQuizzed(_ word: Word, for date: Date) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        // Get or create entry
        let entry = getOrCreateEntry(for: targetDate)
        
        // Check if word is already in the entry
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            // Check if word is not already in the words array
            if !entries[index].words.contains(where: { $0.id == word.id }) {
                // Add the word to the entry at the beginning (most recent first)
                entries[index].words.insert(word, at: 0)
                
                // Save locally
                saveDiaryEntries()
                
                // Save to Firestore if signed in
                if let userId = Auth.auth().currentUser?.uid {
                    createOrUpdateEntryInFirestore(entry: entries[index], userId: userId)
                }
            }
        }
    }
    
    private func createOrUpdateEntryInFirestore(entry: DiaryEntry, userId: String) {
        let entryRef = db.collection("users").document(userId).collection("diaryEntries").document(entry.id.uuidString)
        
        var data: [String: Any] = [
            "date": Timestamp(date: entry.date),
            "words": entry.words.map { encodeWord($0) }
        ]
        
        // Notes - array of notes for each wordId
        var notesData: [String: [[String: Any]]] = [:]
        for (wordId, notes) in entry.notesByWordId {
            notesData[wordId.uuidString] = notes.map { encodeNote($0) }
        }
        if !notesData.isEmpty {
            data["notesByWordId"] = notesData
        }
        
        entryRef.setData(data, merge: true) { error in
            if let error = error {
                // API etkin değilse veya permission hatası varsa sessizce devam et
                let errorCode = (error as NSError).code
                if errorCode == 7 { // Permission denied
                    print("⚠️ Firestore API etkin değil veya permission hatası. Local'de kaydedildi.")
                } else {
                    print("❌ Firestore entry sync error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func isWordQuizzed(_ word: Word, for date: Date) -> Bool {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        // Check if word exists in the entry for this date
        if let entry = getEntry(for: targetDate) {
            return entry.words.contains(where: { $0.id == word.id })
        }
        return false
    }
    
    func getNotes(for wordId: UUID, on date: Date) -> [Note] {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        guard let entry = getEntry(for: targetDate) else { return [] }
        return entry.notesByWordId[wordId] ?? []
    }
    
    func addNote(_ text: String, for wordId: UUID, on date: Date) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // Get or create entry
        let entry = getOrCreateEntry(for: targetDate)
        
        guard let entryIndex = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        
        // Create new note
        let newNote = Note(text: trimmedText)
        
        // Add note to array
        if entries[entryIndex].notesByWordId[wordId] == nil {
            entries[entryIndex].notesByWordId[wordId] = []
        }
        entries[entryIndex].notesByWordId[wordId]?.append(newNote)
        
        // Save locally
        saveDiaryEntries()
        
        // Save to Firestore if signed in
        if let userId = Auth.auth().currentUser?.uid {
            saveNotesToFirestore(for: wordId, on: targetDate, userId: userId, entryId: entry.id)
        }
    }
    
    func updateNote(_ noteId: UUID, text: String, for wordId: UUID, on date: Date, markSuggestionApplied: Bool = false) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        guard let entry = getEntry(for: targetDate),
              let entryIndex = entries.firstIndex(where: { $0.id == entry.id }),
              let noteIndex = entries[entryIndex].notesByWordId[wordId]?.firstIndex(where: { $0.id == noteId }) else { return }
        
        // Update note text
        let oldNote = entries[entryIndex].notesByWordId[wordId]![noteIndex]
        let newSuggestionFlag: Bool
        if markSuggestionApplied {
            newSuggestionFlag = true
        } else if trimmedText != oldNote.text {
            // Öneriyi uyguladıktan sonra kullanıcı cümleyi değiştirdiyse Suggestion tekrar açılsın
            newSuggestionFlag = false
        } else {
            newSuggestionFlag = oldNote.suggestionApplyUsed
        }
        entries[entryIndex].notesByWordId[wordId]![noteIndex] = Note(
            id: oldNote.id,
            text: trimmedText,
            createdAt: oldNote.createdAt,
            suggestionApplyUsed: newSuggestionFlag
        )
        
        // Save locally
        saveDiaryEntries()
        
        // Save to Firestore if signed in
        if let userId = Auth.auth().currentUser?.uid {
            saveNotesToFirestore(for: wordId, on: targetDate, userId: userId, entryId: entry.id)
        }
    }
    
    func deleteNote(_ noteId: UUID, for wordId: UUID, on date: Date) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        guard let entry = getEntry(for: targetDate),
              let entryIndex = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        
        // Remove note from array
        entries[entryIndex].notesByWordId[wordId]?.removeAll(where: { $0.id == noteId })
        
        // If array is empty, remove the key
        if entries[entryIndex].notesByWordId[wordId]?.isEmpty == true {
            entries[entryIndex].notesByWordId.removeValue(forKey: wordId)
        }
        
        // Save locally
        saveDiaryEntries()
        
        // Save to Firestore if signed in
        if let userId = Auth.auth().currentUser?.uid {
            saveNotesToFirestore(for: wordId, on: targetDate, userId: userId, entryId: entry.id)
        }
    }
    
    private func saveDiaryEntries() {
        do {
            let encoded = try JSONEncoder().encode(entries)
            guard let uid = Auth.auth().currentUser?.uid,
                  let key = diaryStorageKey(forUserId: uid) else { return }
            UserDefaults.standard.set(encoded, forKey: key)
        } catch {
            print("❌ Diary entries kaydedilemedi: \(error)")
        }
    }
    
    private func loadDiaryEntries() {
        guard let uid = Auth.auth().currentUser?.uid,
              let key = diaryStorageKey(forUserId: uid) else {
            entries = []
            return
        }

        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: key) ?? defaults.data(forKey: Self.legacyDiaryEntriesKey)
        if let data {
            do {
                let decoded = try JSONDecoder().decode([DiaryEntry].self, from: data)
                entries = decoded
            } catch {
                print("❌ Diary entries yüklenemedi: \(error)")
                entries = []
            }

            // One-time migration from legacy global key -> per-user key
            if defaults.data(forKey: key) == nil, defaults.data(forKey: Self.legacyDiaryEntriesKey) != nil {
                saveDiaryEntries()
                defaults.removeObject(forKey: Self.legacyDiaryEntriesKey)
            }
        } else {
            entries = []
        }
    }
    
    // MARK: - Firestore Methods
    
    private func syncFromFirestore(userId: String) {
        // Firestore'dan tüm diary entries'i çek
        let entriesRef = db.collection("users").document(userId).collection("diaryEntries")
        
        listener?.remove()
        listener = nil

        cloudSyncUserMessage = nil

        // Yeni listener bağlamadan önce bellekteki listeyi temizle (eski hesabın verisi bir frame bile görünmesin).
        // UserDefaults'a boş yazmıyoruz; listener hata verirse yerel veri `loadDiaryEntries()` ile geri gelir.
        self.entries = []

        listener = entriesRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                let errorCode = (error as NSError).code
                DispatchQueue.main.async {
                    self.cloudSyncUserMessage = String(localized: "Couldn’t sync your diary with the cloud. Showing entries saved on this device.")
                    self.loadDiaryEntries()
                }
                if errorCode != 7 {
                    print("❌ Firestore sync error: \(error.localizedDescription)")
                } else {
                    print("⚠️ Firestore permission denied; using local diary if available.")
                }
                return
            }
            
            guard let documents = snapshot?.documents else { return }

            if documents.isEmpty {
                // Yeni hesap / henüz diary yok: local merge yapma.
                DispatchQueue.main.async {
                    self.cloudSyncUserMessage = nil
                    self.entries = []
                    self.saveDiaryEntries()
                }
                return
            }
            
            var firestoreEntries: [DiaryEntry] = []
            
            for document in documents {
                do {
                    let data = document.data()
                    let entryId = UUID(uuidString: document.documentID) ?? UUID()
                    
                    // Date
                    guard let timestamp = data["date"] as? Timestamp else { continue }
                    let date = timestamp.dateValue()
                    
                    // Words
                    var words: [Word] = []
                    if let wordsData = data["words"] as? [[String: Any]] {
                        for wordData in wordsData {
                            if let word = self.decodeWord(from: wordData) {
                                words.append(word)
                            }
                        }
                    }
                    
                    // Notes - support both old format (String) and new format (Array)
                    var notesByWordId: [UUID: [Note]] = [:]
                    if let notesData = data["notesByWordId"] as? [String: Any] {
                        for (wordIdString, notesValue) in notesData {
                            guard let wordId = UUID(uuidString: wordIdString) else { continue }
                            
                            // New format: array of notes
                            if let notesArray = notesValue as? [[String: Any]] {
                                var notes: [Note] = []
                                for noteData in notesArray {
                                    if let note = decodeNote(from: noteData) {
                                        notes.append(note)
                                    }
                                }
                                notesByWordId[wordId] = notes
                            }
                            // Old format: single string (migration support)
                            else if let noteString = notesValue as? String, !noteString.isEmpty {
                                // Split by newlines and create separate notes
                                let lines = noteString.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                notesByWordId[wordId] = lines.map { Note(text: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            }
                        }
                    }
                    
                    let entry = DiaryEntry(id: entryId, date: date, words: words, notesByWordId: notesByWordId)
                    firestoreEntries.append(entry)
                } catch {
                    print("❌ Entry decode error: \(error)")
                }
            }
            
            // IMPORTANT:
            // Never merge previous-account local `entries` into the newly signed-in user's Firestore view.
            // That merge path was a common source of "new account shows old diary/stats".
            let sorted = firestoreEntries.sorted { $0.date < $1.date }
            DispatchQueue.main.async {
                self.cloudSyncUserMessage = nil
                self.entries = sorted
                self.saveDiaryEntries()
            }
        }
    }
    
    private func saveNotesToFirestore(for wordId: UUID, on date: Date, userId: String, entryId: UUID) {
        guard let entry = entries.first(where: { $0.id == entryId }),
              let notes = entry.notesByWordId[wordId] else { return }
        
        let entryRef = db.collection("users").document(userId).collection("diaryEntries").document(entryId.uuidString)
        let notesPath = "notesByWordId.\(wordId.uuidString)"
        
        if notes.isEmpty {
            // Remove notes array if empty
            entryRef.updateData([notesPath: FieldValue.delete()]) { error in
                if let error = error {
                    let errorCode = (error as NSError).code
                    if errorCode == 7 {
                        print("⚠️ Firestore API etkin değil. Local'de silindi.")
                    } else {
                        print("❌ Firestore notes delete error: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Update notes array
            let notesData = notes.map { encodeNote($0) }
            entryRef.updateData([notesPath: notesData]) { error in
                if let error = error {
                    let errorCode = (error as NSError).code
                    if errorCode == 7 {
                        print("⚠️ Firestore API etkin değil. Local'de kaydedildi.")
                    } else {
                        print("❌ Firestore notes update error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func encodeNote(_ note: Note) -> [String: Any] {
        var d: [String: Any] = [
            "id": note.id.uuidString,
            "text": note.text,
            "createdAt": Timestamp(date: note.createdAt),
            "suggestionApplyUsed": note.suggestionApplyUsed
        ]
        return d
    }
    
    private func decodeNote(from data: [String: Any]) -> Note? {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let text = data["text"] as? String else {
            return nil
        }
        
        var createdAt = Date()
        if let timestamp = data["createdAt"] as? Timestamp {
            createdAt = timestamp.dateValue()
        }
        
        let suggestionApplyUsed = data["suggestionApplyUsed"] as? Bool ?? false
        
        return Note(id: id, text: text, createdAt: createdAt, suggestionApplyUsed: suggestionApplyUsed)
    }
    
    private func encodeWord(_ word: Word) -> [String: Any] {
        var data: [String: Any] = [
            "id": word.id.uuidString,
            "word": word.word,
            "definition": word.definition,
            "exampleSentence": word.exampleSentence
        ]
        if let phonetic = word.phonetic {
            data["phonetic"] = phonetic
        }
        if let s2 = word.exampleSentence2 { data["exampleSentence2"] = s2 }
        if let s3 = word.exampleSentence3 { data["exampleSentence3"] = s3 }
        if let c = word.cefrLevel { data["cefrLevel"] = c }
        if let d = word.domainTag { data["domainTag"] = d }
        if let pos = word.partOfSpeech { data["partOfSpeech"] = pos }
        if let r = word.registerTag { data["registerTag"] = r }
        if let f = word.frequencyBand { data["frequencyBand"] = f }
        return data
    }
    
    private func decodeWord(from data: [String: Any]) -> Word? {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let word = data["word"] as? String,
              let definition = data["definition"] as? String,
              let exampleSentence = data["exampleSentence"] as? String else {
            return nil
        }
        let phonetic = data["phonetic"] as? String
        let exampleSentence2 = data["exampleSentence2"] as? String
        let exampleSentence3 = data["exampleSentence3"] as? String
        let cefrLevel = data["cefrLevel"] as? String
        let domainTag = data["domainTag"] as? String
        let partOfSpeech = data["partOfSpeech"] as? String
        let registerTag = data["registerTag"] as? String
        let frequencyBand: Int? = {
            if let i = data["frequencyBand"] as? Int { return i }
            if let i64 = data["frequencyBand"] as? Int64 { return Int(i64) }
            if let n = data["frequencyBand"] as? NSNumber { return n.intValue }
            return nil
        }()
        return Word(
            id: id,
            word: word,
            definition: definition,
            exampleSentence: exampleSentence,
            phonetic: phonetic,
            exampleSentence2: exampleSentence2,
            exampleSentence3: exampleSentence3,
            cefrLevel: cefrLevel,
            domainTag: domainTag,
            partOfSpeech: partOfSpeech,
            registerTag: registerTag,
            frequencyBand: frequencyBand
        )
    }
}
