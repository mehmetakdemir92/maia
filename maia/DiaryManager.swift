//
//  DiaryManager.swift
//  maia
//
//  Created by Mehmet Akdemir on 22.01.2026.
//

import Foundation
import Combine
import CryptoKit
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    /// true after applying a suggestion via "Use this example"; hides the Suggestion button.
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
    @Published var entries: [DiaryEntry] = [] {
        didSet { reconcileCloudSyncBanner() }
    }

    /// Shown on Firestore listener error; cleared on successful sync or clearCloudSyncUserMessage().
    @Published private(set) var cloudSyncUserMessage: String?

    /// UI: whether the diary has any words or notes.
    var hasSyncableDiaryContent: Bool {
        diaryHasSyncableContent(entries)
    }

    /// UI: cloud warning is shown only when diary has content.
    var shouldShowCloudSyncBanner: Bool {
        hasSyncableDiaryContent && cloudSyncUserMessage != nil
    }

    private let db = Firestore.firestore()
    private var lastObservedAuthUID: String?
    /// No live listener; one-shot read/write only.
    private var isUploadingToCloud = false
    private var isPullingFromFirestore = false
    private var lastUploadedFingerprint: String?
    private var lastKnownRemoteFingerprint: String?
    private static let legacyDiaryEntriesKey = "diaryEntries"
    private static let lastUploadedFingerprintPrefix = "diaryLastUploadedFingerprint."
    private static let diarySchemaVersion = 2

    /// Diary day boundaries use the Istanbul calendar app-wide (matches DiaryView).
    private var diaryCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        return cal
    }

    private lazy var diaryDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = diaryCalendar
        formatter.timeZone = diaryCalendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func diaryStorageKey(forUserId uid: String?) -> String? {
        guard let uid, !uid.isEmpty else { return nil }
        return "diaryEntries.\(uid)"
    }

    private func lastUploadedFingerprintKey(forUserId uid: String) -> String {
        Self.lastUploadedFingerprintPrefix + uid
    }

    private func loadPersistedSyncState(userId: String) {
        let defaults = UserDefaults.standard
        lastUploadedFingerprint = defaults.string(forKey: lastUploadedFingerprintKey(forUserId: userId))
    }

    private func persistUploadedFingerprint(_ fingerprint: String, userId: String) {
        lastUploadedFingerprint = fingerprint
        UserDefaults.standard.set(fingerprint, forKey: lastUploadedFingerprintKey(forUserId: userId))
    }

    private func resetSyncStateForNewUser() {
        isUploadingToCloud = false
        lastUploadedFingerprint = nil
        lastKnownRemoteFingerprint = nil
    }

    private func diaryDayKey(for date: Date) -> String {
        let day = diaryCalendar.startOfDay(for: date)
        return diaryDayFormatter.string(from: day)
    }

    private func dateFromDiaryDayKey(_ key: String) -> Date? {
        diaryDayFormatter.date(from: key)
    }

    private func stableEntryId(for date: Date) -> UUID {
        let dayKey = diaryDayKey(for: date)
        let hash = SHA256.hash(data: Data(dayKey.utf8))
        var bytes = Array(hash.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func firestoreDocumentId(for entry: DiaryEntry) -> String {
        diaryDayKey(for: entry.date)
    }

    private func isDiaryDayDocumentId(_ documentId: String) -> Bool {
        dateFromDiaryDayKey(documentId) != nil
    }

    private func normalizedEntry(_ entry: DiaryEntry) -> DiaryEntry {
        let day = diaryCalendar.startOfDay(for: entry.date)
        return DiaryEntry(
            id: stableEntryId(for: day),
            date: day,
            words: entry.words,
            notesByWordId: entry.notesByWordId
        )
    }

    private func mergeDiaryEntries(local: [DiaryEntry], remote: [DiaryEntry]) -> [DiaryEntry] {
        var byDayKey: [String: DiaryEntry] = [:]

        func absorb(_ entry: DiaryEntry) {
            let normalized = normalizedEntry(entry)
            let key = diaryDayKey(for: normalized.date)
            if let existing = byDayKey[key] {
                byDayKey[key] = mergeTwoEntries(existing, normalized)
            } else {
                byDayKey[key] = normalized
            }
        }

        for entry in local { absorb(entry) }
        for entry in remote { absorb(entry) }

        return byDayKey.values.sorted { $0.date < $1.date }
    }

    private func mergeTwoEntries(_ a: DiaryEntry, _ b: DiaryEntry) -> DiaryEntry {
        var words = a.words
        for word in b.words where !words.contains(where: { $0.id == word.id }) {
            words.append(word)
        }

        var notesByWordId = a.notesByWordId
        for (wordId, remoteNotes) in b.notesByWordId {
            if var existing = notesByWordId[wordId] {
                for note in remoteNotes where !existing.contains(where: { $0.id == note.id }) {
                    existing.append(note)
                }
                notesByWordId[wordId] = existing
            } else {
                notesByWordId[wordId] = remoteNotes
            }
        }

        let day = diaryCalendar.startOfDay(for: a.date)
        return DiaryEntry(
            id: stableEntryId(for: day),
            date: day,
            words: words,
            notesByWordId: notesByWordId
        )
    }

    init() {
        loadDiaryEntries()
        reconcileCloudSyncBanner()
        lastObservedAuthUID = Auth.auth().currentUser?.uid
        setupPronunciationObserver()
        setupAuthListener()
        // If already signed in, skip auth listener and start sync like WordProgress/StreakManager.
        if let userId = Auth.auth().currentUser?.uid {
            loadPersistedSyncState(userId: userId)
            pullFromFirestoreOnce(userId: userId)
        }
    }
    
    private static func canSyncDiaryWithFirestore(user: User?) -> Bool {
        user != nil
    }

    private func diaryHasSyncableContent(_ entries: [DiaryEntry]) -> Bool {
        entries.contains { !$0.words.isEmpty || !$0.notesByWordId.isEmpty }
    }

    private func shouldSurfaceCloudSyncError(_ error: Error, localEntries: [DiaryEntry]) -> Bool {
        // Do not show cloud warning when diary is empty (normal for new users).
        guard diaryHasSyncableContent(localEntries) else { return false }

        let nsError = error as NSError
        if nsError.code == 7,
           !Self.canSyncDiaryWithFirestore(user: Auth.auth().currentUser) {
            return false
        }
        return true
    }

    private func setCloudSyncUserMessage(_ message: String?) {
        guard let message, diaryHasSyncableContent(entries) else {
            cloudSyncUserMessage = nil
            return
        }
        cloudSyncUserMessage = message
    }

    private func reconcileCloudSyncBanner() {
        if !diaryHasSyncableContent(entries) {
            cloudSyncUserMessage = nil
        }
    }

    private func setupPronunciationObserver() {
        NotificationCenter.default.addObserver(
            forName: .pronunciationAudioURLResolved,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let lemma = notification.userInfo?["lemma"] as? String,
                  let url = notification.userInfo?["audioURL"] as? String else { return }
            self?.applyPronunciationAudioURL(url, lemma: lemma)
        }
    }

    /// Updates diary words when a cloud pronunciation URL is generated.
    func applyPronunciationAudioURL(_ url: String, lemma: String) {
        var changed = false
        for entryIndex in entries.indices {
            var words = entries[entryIndex].words
            var entryChanged = false
            for wordIndex in words.indices {
                let normalized = WordPronunciationService.normalizeLemma(words[wordIndex].word)
                guard normalized == lemma, words[wordIndex].pronunciationAudioURL != url else { continue }
                words[wordIndex] = words[wordIndex].withPronunciationAudioURL(url)
                entryChanged = true
            }
            if entryChanged {
                entries[entryIndex] = DiaryEntry(
                    id: entries[entryIndex].id,
                    date: entries[entryIndex].date,
                    words: words,
                    notesByWordId: entries[entryIndex].notesByWordId
                )
                changed = true
            }
        }
        if changed {
            saveDiaryEntries()
        }
    }

    private func setupAuthListener() {
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
                    self.resetSyncStateForNewUser()
                    self.entries = []
                    if let prevUserId = previous,
                       let oldKey = self.diaryStorageKey(forUserId: prevUserId) {
                        UserDefaults.standard.removeObject(forKey: oldKey)
                    }
                    UserDefaults.standard.removeObject(forKey: Self.legacyDiaryEntriesKey)
                } else {
                    self.loadDiaryEntries()
                }
                self.loadPersistedSyncState(userId: uid)
                self.pullFromFirestoreOnce(userId: uid)
            } else {
                self.cloudSyncUserMessage = nil
                self.resetSyncStateForNewUser()
                self.entries = []
                if let prevUserId = previous,
                   let oldKey = self.diaryStorageKey(forUserId: prevUserId) {
                    UserDefaults.standard.removeObject(forKey: oldKey)
                }
                UserDefaults.standard.removeObject(forKey: Self.legacyDiaryEntriesKey)
            }
        }
    }
    
    /// Auto bulk upload disabled (loop prevention). Cloud writes: quiz / note only.
    func syncDiaryToCloudIfNeeded() { }

    private func cloudContentFingerprint(_ entries: [DiaryEntry]) -> String {
        let parts = entries
            .map { normalizedEntry($0) }
            .filter { !$0.words.isEmpty || !$0.notesByWordId.isEmpty }
            .sorted { $0.date < $1.date }
            .map { entry -> String in
                let day = diaryDayKey(for: entry.date)
                let wordIds = entry.words.map(\.id.uuidString).sorted().joined(separator: ",")
                let noteIds = entry.notesByWordId.values
                    .flatMap { $0.map(\.id.uuidString) }
                    .sorted()
                    .joined(separator: ",")
                return "\(day)|w:\(wordIds)|n:\(noteIds)"
            }
        return parts.joined(separator: ";;")
    }

    private func entriesContentEqual(_ a: [DiaryEntry], _ b: [DiaryEntry]) -> Bool {
        cloudContentFingerprint(a.map { normalizedEntry($0) })
            == cloudContentFingerprint(b.map { normalizedEntry($0) })
    }

    private func syncLocalToFirestore(
        userId: String,
        entriesOverride: [DiaryEntry]? = nil,
        force: Bool = false,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard !isUploadingToCloud else {
            if force {
                print("⚠️ Diary upload skipped — already uploading")
            }
            completion?(false)
            return
        }

        let entriesToUpload = (entriesOverride ?? entries)
            .map { normalizedEntry($0) }
            .filter { !$0.words.isEmpty || !$0.notesByWordId.isEmpty }
        guard !entriesToUpload.isEmpty else {
            print("⚠️ Diary upload skipped — no words in local entries")
            completion?(false)
            return
        }

        let fingerprint = cloudContentFingerprint(entriesToUpload)
        if !force {
            let remoteFP = lastKnownRemoteFingerprint ?? ""
            if !remoteFP.isEmpty, fingerprint == lastUploadedFingerprint, fingerprint == remoteFP {
                completion?(true)
                return
            }
        }

        let totalWords = entriesToUpload.reduce(0) { $0 + $1.words.count }
        print("📤 Diary uploading \(entriesToUpload.count) day(s), \(totalWords) word(s), force=\(force)")

        isUploadingToCloud = true

        let batch = db.batch()
        for entry in entriesToUpload {
            let documentId = firestoreDocumentId(for: entry)
            let ref = db.collection("users").document(userId).collection("diaryEntries").document(documentId)
            batch.setData(firestorePayload(for: entry), forDocument: ref, merge: true)
        }

        batch.commit { [weak self] error in
            guard let self else { return }
            defer { self.isUploadingToCloud = false }

            if let error = error {
                let code = (error as NSError).code
                if self.shouldSurfaceCloudSyncError(error, localEntries: entriesToUpload) {
                    DispatchQueue.main.async {
                        if code == 7 {
                            self.setCloudSyncUserMessage(String(localized: "Couldn’t save your diary to the cloud. Check that you’re signed in."))
                        } else {
                            self.setCloudSyncUserMessage(String(localized: "Couldn’t sync your diary with the cloud. Showing entries saved on this device."))
                        }
                    }
                }
                print("❌ Diary batch sync failed: \(error.localizedDescription)")
                completion?(false)
                return
            }

            self.persistUploadedFingerprint(fingerprint, userId: userId)
            self.lastKnownRemoteFingerprint = fingerprint
            DispatchQueue.main.async { self.cloudSyncUserMessage = nil }
            print("✅ Diary batch synced \(entriesToUpload.count) day(s) → users/\(userId)/diaryEntries/")
            completion?(true)
        }
    }

    private func firestorePayload(for entry: DiaryEntry) -> [String: Any] {
        var data: [String: Any] = [
            "date": Timestamp(date: entry.date),
            "entryId": entry.id.uuidString,
            "schemaVersion": Self.diarySchemaVersion,
            "updatedAt": Timestamp(date: Date()),
            "words": entry.words.map { encodeWord($0) }
        ]
        var notesData: [String: [[String: Any]]] = [:]
        for (wordId, notes) in entry.notesByWordId {
            notesData[wordId.uuidString] = notes.map { encodeNote($0) }
        }
        if !notesData.isEmpty {
            data["notesByWordId"] = notesData
        }
        return data
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
        let targetDate = diaryCalendar.startOfDay(for: date)

        if let existingEntry = entries.first(where: { diaryCalendar.isDate($0.date, inSameDayAs: targetDate) }) {
            return existingEntry
        }

        let newEntry = DiaryEntry(id: stableEntryId(for: targetDate), date: targetDate, words: [])
        entries.append(newEntry)
        saveDiaryEntries()
        return newEntry
    }
    
    func getEntry(for date: Date) -> DiaryEntry? {
        let targetDate = diaryCalendar.startOfDay(for: date)
        return entries.first(where: { diaryCalendar.isDate($0.date, inSameDayAs: targetDate) })
    }
    
    func markWordAsQuizzed(_ word: Word, for date: Date) {
        let targetDate = diaryCalendar.startOfDay(for: date)
        
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
                
                if let userId = Auth.auth().currentUser?.uid {
                    createOrUpdateEntryInFirestore(entry: entries[index], userId: userId)
                }

                Task {
                    await enrichAndUpdateWord(word, on: targetDate)
                }
            }
        }
    }

    // MARK: - Word metadata (phonetic / partOfSpeech)

    private func needsMetadataEnrichment(_ word: Word) -> Bool {
        let phoneticMissing = word.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        let posMissing = word.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        return phoneticMissing || posMissing
    }

    private func enrichWord(_ word: Word, date: Date) async -> Word {
        var phonetic = word.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines)
        if phonetic?.isEmpty == true { phonetic = nil }
        var partOfSpeech = word.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if partOfSpeech?.isEmpty == true { partOfSpeech = nil }

        guard phonetic == nil || partOfSpeech == nil else { return word }

        let dayKey = diaryDayKey(for: date)
        let packEntry = await MainActor.run {
            WordPackStore.shared.entries(for: dayKey)
                .first { $0.word.lowercased() == word.word.lowercased() }
        }

        if phonetic == nil, let packPhonetic = packEntry?.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines),
           !packPhonetic.isEmpty {
            phonetic = packPhonetic
        }
        if partOfSpeech == nil, let packPOS = packEntry?.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !packPOS.isEmpty {
            partOfSpeech = packPOS
        }

        if phonetic == nil {
            phonetic = PhoneticLookup.cachedIPA(for: word.word)
        }
        if phonetic == nil {
            phonetic = await PhoneticLookup.ipa(for: word.word)
        }

        if phonetic == word.phonetic && partOfSpeech == word.partOfSpeech {
            return word
        }

        return Word(
            id: word.id,
            word: word.word,
            definition: word.definition,
            exampleSentence: word.exampleSentence,
            phonetic: phonetic,
            pronunciationAudioURL: word.pronunciationAudioURL,
            exampleSentence2: word.exampleSentence2,
            exampleSentence3: word.exampleSentence3,
            cefrLevel: word.cefrLevel,
            domainTag: word.domainTag,
            partOfSpeech: partOfSpeech ?? word.partOfSpeech,
            registerTag: word.registerTag,
            frequencyBand: word.frequencyBand
        )
    }

    private func enrichAndUpdateWord(_ word: Word, on date: Date) async {
        let enriched = await enrichWord(word, date: date)
        guard enriched != word else { return }

        await MainActor.run {
            guard let entry = getEntry(for: date),
                  let entryIndex = entries.firstIndex(where: { $0.id == entry.id }),
                  let wordIndex = entries[entryIndex].words.firstIndex(where: { $0.id == word.id }) else {
                return
            }
            entries[entryIndex].words[wordIndex] = enriched
            saveDiaryEntries()
            if let userId = Auth.auth().currentUser?.uid {
                createOrUpdateEntryInFirestore(entry: entries[entryIndex], userId: userId)
            }
        }
    }

    private func enrichAllEntriesIfNeeded() {
        Task {
            var updated = entries
            var changed = false

            for entryIndex in updated.indices {
                for wordIndex in updated[entryIndex].words.indices {
                    let original = updated[entryIndex].words[wordIndex]
                    guard needsMetadataEnrichment(original) else { continue }
                    let enriched = await enrichWord(original, date: updated[entryIndex].date)
                    if enriched != original {
                        updated[entryIndex].words[wordIndex] = enriched
                        changed = true
                    }
                }
            }

            guard changed else { return }
            await MainActor.run {
                entries = updated
                saveDiaryEntries()
            }
        }
    }
    
    private func createOrUpdateEntryInFirestore(entry: DiaryEntry, userId: String) {
        guard !isUploadingToCloud else { return }

        let normalized = normalizedEntry(entry)
        guard !normalized.words.isEmpty || !normalized.notesByWordId.isEmpty else { return }

        let documentId = firestoreDocumentId(for: normalized)
        let entryRef = db.collection("users").document(userId).collection("diaryEntries").document(documentId)
        let data = firestorePayload(for: normalized)

        isUploadingToCloud = true
        entryRef.setData(data, merge: true) { [weak self] error in
            guard let self else { return }
            defer { self.isUploadingToCloud = false }

            if let error = error {
                let errorCode = (error as NSError).code
                if errorCode == 7 {
                    print("⚠️ Diary Firestore permission denied. Saved locally only.")
                } else {
                    print("❌ Diary Firestore sync error: \(error.localizedDescription)")
                }
                return
            }
            // Do not mark full diary fingerprint on single-day write — done when batch completes.
            print("✅ Diary synced: users/\(userId)/diaryEntries/\(documentId) (\(normalized.words.count) words)")
        }
    }

    func isWordQuizzed(_ word: Word, for date: Date) -> Bool {
        let targetDate = diaryCalendar.startOfDay(for: date)
        
        // Check if word exists in the entry for this date
        if let entry = getEntry(for: targetDate) {
            return entry.words.contains(where: { $0.id == word.id })
        }
        return false
    }
    
    func getNotes(for wordId: UUID, on date: Date) -> [Note] {
        let targetDate = diaryCalendar.startOfDay(for: date)
        
        guard let entry = getEntry(for: targetDate) else { return [] }
        return entry.notesByWordId[wordId] ?? []
    }
    
    func addNote(_ text: String, for wordId: UUID, on date: Date) {
        let targetDate = diaryCalendar.startOfDay(for: date)
        
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
        let targetDate = diaryCalendar.startOfDay(for: date)
        
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
            // Re-show Suggestion if user edits the sentence after applying a suggestion
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
        let targetDate = diaryCalendar.startOfDay(for: date)
        
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
        enrichAllEntriesIfNeeded()
    }
    
    // MARK: - Firestore Methods

    /// No live listener — one-shot read (avoids per-second snapshot loops).
    private func pullFromFirestoreOnce(userId: String) {
        guard !isPullingFromFirestore else { return }

        loadDiaryEntries()
        let localSnapshot = entries

        guard Self.canSyncDiaryWithFirestore(user: Auth.auth().currentUser) else {
            cloudSyncUserMessage = nil
            return
        }

        isPullingFromFirestore = true
        cloudSyncUserMessage = nil

        db.collection("users").document(userId).collection("diaryEntries")
            .getDocuments { [weak self] snapshot, error in
                guard let self else { return }
                defer { self.isPullingFromFirestore = false }

                if let error = error {
                    DispatchQueue.main.async {
                        if self.shouldSurfaceCloudSyncError(error, localEntries: localSnapshot) {
                            self.setCloudSyncUserMessage(String(localized: "Couldn’t sync your diary with the cloud. Showing entries saved on this device."))
                        } else {
                            self.setCloudSyncUserMessage(nil)
                        }
                        self.loadDiaryEntries()
                    }
                    if (error as NSError).code != 7 {
                        print("❌ Diary pull error: \(error.localizedDescription)")
                    }
                    return
                }

                let firestoreEntries = (snapshot?.documents ?? []).compactMap { self.decodeDiaryEntry(from: $0) }
                self.lastKnownRemoteFingerprint = self.cloudContentFingerprint(
                    firestoreEntries.map { self.normalizedEntry($0) }
                )
                let merged = self.mergeDiaryEntries(local: localSnapshot, remote: firestoreEntries)

                DispatchQueue.main.async {
                    if !self.entriesContentEqual(self.entries, merged) {
                        self.entries = merged
                        self.saveDiaryEntries()
                    }
                    self.cloudSyncUserMessage = nil
                    self.enrichAllEntriesIfNeeded()
                }
            }
    }

    private func decodeDiaryEntry(from document: QueryDocumentSnapshot) -> DiaryEntry? {
        let data = document.data()
        let documentId = document.documentID

        let entryDate: Date
        if let dayFromDocId = dateFromDiaryDayKey(documentId) {
            entryDate = diaryCalendar.startOfDay(for: dayFromDocId)
        } else if let timestamp = data["date"] as? Timestamp {
            entryDate = diaryCalendar.startOfDay(for: timestamp.dateValue())
        } else {
            return nil
        }

        let entryId: UUID
        if let storedId = data["entryId"] as? String, let uuid = UUID(uuidString: storedId) {
            entryId = uuid
        } else if let dayFromDocId = dateFromDiaryDayKey(documentId) {
            entryId = stableEntryId(for: dayFromDocId)
        } else if let legacyId = UUID(uuidString: documentId) {
            entryId = legacyId
        } else {
            entryId = stableEntryId(for: entryDate)
        }

        var words: [Word] = []
        if let wordsData = data["words"] as? [[String: Any]] {
            for wordData in wordsData {
                if let word = decodeWord(from: wordData) {
                    words.append(word)
                }
            }
        }

        var notesByWordId: [UUID: [Note]] = [:]
        if let notesData = data["notesByWordId"] as? [String: Any] {
            for (wordIdString, notesValue) in notesData {
                guard let wordId = UUID(uuidString: wordIdString) else { continue }

                if let notesArray = notesValue as? [[String: Any]] {
                    var notes: [Note] = []
                    for noteData in notesArray {
                        if let note = decodeNote(from: noteData) {
                            notes.append(note)
                        }
                    }
                    notesByWordId[wordId] = notes
                } else if let noteString = notesValue as? String, !noteString.isEmpty {
                    let lines = noteString.components(separatedBy: "\n").filter {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    notesByWordId[wordId] = lines.map {
                        Note(text: $0.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }

        return DiaryEntry(id: entryId, date: entryDate, words: words, notesByWordId: notesByWordId)
    }
    
    private func saveNotesToFirestore(for wordId: UUID, on date: Date, userId: String, entryId: UUID) {
        guard let entry = entries.first(where: { $0.id == entryId }) else { return }
        createOrUpdateEntryInFirestore(entry: entry, userId: userId)
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
        if let audio = word.pronunciationAudioURL {
            data["pronunciationAudioURL"] = audio
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
        let pronunciationAudioURL = data["pronunciationAudioURL"] as? String
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
            pronunciationAudioURL: pronunciationAudioURL,
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
