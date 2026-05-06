//
//  DiaryManager.swift
//  vocability
//
//  Created by Mehmet Akdemir on 22.01.2026.
//

import Foundation
import Combine

struct DiaryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    var words: [Word]
    var notesByWordId: [UUID: String] // wordId -> note
    
    init(id: UUID = UUID(), date: Date, words: [Word] = [], notesByWordId: [UUID: String] = [:]) {
        self.id = id
        self.date = date
        self.words = words
        self.notesByWordId = notesByWordId
    }
}

class DiaryManager: ObservableObject {
    @Published var entries: [DiaryEntry] = []
    
    init() {
        loadDiaryEntries()
    }
    
    func resetDiaryDataForDebug() {
        entries = []
        UserDefaults.standard.removeObject(forKey: "diaryEntries")
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
                // Add the word to the entry
                entries[index].words.append(word)
                saveDiaryEntries()
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
    
    func getNote(for wordId: UUID, on date: Date) -> String? {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        guard let entry = getEntry(for: targetDate) else { return nil }
        return entry.notesByWordId[wordId]
    }
    
    func saveNote(_ note: String, for wordId: UUID, on date: Date) {
        let calendar = Calendar.current
        let targetDate = calendar.startOfDay(for: date)
        
        // Get or create entry
        let entry = getOrCreateEntry(for: targetDate)
        
        guard let entryIndex = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        
        // Update or add note
        entries[entryIndex].notesByWordId[wordId] = note.isEmpty ? nil : note
        saveDiaryEntries()
    }
    
    private func saveDiaryEntries() {
        do {
            let encoded = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(encoded, forKey: "diaryEntries")
        } catch {
            print("❌ Diary entries kaydedilemedi: \(error)")
        }
    }
    
    private func loadDiaryEntries() {
        if let data = UserDefaults.standard.data(forKey: "diaryEntries") {
            do {
                let decoded = try JSONDecoder().decode([DiaryEntry].self, from: data)
                entries = decoded
            } catch {
                print("❌ Diary entries yüklenemedi: \(error)")
                entries = []
            }
        } else {
            entries = []
        }
    }
}
