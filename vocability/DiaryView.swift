//
//  DiaryView.swift
//  vocability
//
//  Created by Mehmet Akdemir on 22.01.2026.
//

import SwiftUI

struct DiaryView: View {
    @EnvironmentObject var diaryManager: DiaryManager
    @EnvironmentObject var userManager: UserManager
    @State private var expandedWordIds: Set<UUID> = []
    @State private var groupedDays: [String: [Date]] = [:]
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
    
    var body: some View {
        NavigationStack {
            let sortedMonths = groupedDays.keys.sorted(by: >)
            
            if sortedMonths.isEmpty {
                // Empty state
                ScrollView {
                    VStack(spacing: 20) {
                        
                        Text("No Diary Entries Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("Complete quizzes to start building your vocabulary diary!")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 100)
                }
                .background(AppColors.background)
                .navigationTitle("Diary")
                .navigationBarTitleDisplayMode(.large)
            } else {
                List {
                    ForEach(sortedMonths, id: \.self) { monthKey in
                        MonthSectionView(
                            monthKey: monthKey,
                            days: groupedDays[monthKey] ?? [],
                            diaryManager: diaryManager,
                            expandedWordIds: $expandedWordIds,
                            onToggle: handleToggle
                        )
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppColors.background)
                .navigationTitle("Diary")
                .navigationBarTitleDisplayMode(.large)
            }
        }
        .onAppear {
            updateGroupedDays()
        }
        .onChange(of: diaryManager.entries) { _ in
            // DiaryManager'da değişiklik olduğunda groupedDays'i güncelle
            updateGroupedDays()
        }
    }
    
    private func updateGroupedDays() {
        // Sadece entry'leri olan günleri kullan - çok daha hızlı
        var grouped: [String: [Date]] = [:]
        
        for entry in diaryManager.entries {
            guard !entry.words.isEmpty else { continue }
            let monthKey = Self.dateFormatter.string(from: entry.date).uppercased()
            if grouped[monthKey] == nil {
                grouped[monthKey] = []
            }
            grouped[monthKey]?.append(entry.date)
        }
        
        // Her ay için günleri sırala
        for key in grouped.keys {
            grouped[key]?.sort(by: >)
        }
        
        groupedDays = grouped
    }
    
    private func handleToggle(wordId: UUID, date: Date) {
        if expandedWordIds.contains(wordId) {
            expandedWordIds.remove(wordId)
        } else {
            expandedWordIds.insert(wordId)
        }
    }
}

struct MonthSectionView: View {
    let monthKey: String
    let days: [Date]
    @ObservedObject var diaryManager: DiaryManager
    @Binding var expandedWordIds: Set<UUID>
    let onToggle: (UUID, Date) -> Void
    
    var body: some View {
        Section {
            ForEach(days, id: \.self) { date in
                dayWordsView(for: date)
            }
        } header: {
            Text(monthKey)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
        }
    }
    
    @ViewBuilder
    private func dayWordsView(for date: Date) -> some View {
        if let entry = diaryManager.getEntry(for: date), !entry.words.isEmpty {
            ForEach(entry.words) { word in
                WordRowView(
                    word: word,
                    date: date,
                    diaryManager: diaryManager,
                    isExpanded: expandedWordIds.contains(word.id),
                    onToggle: {
                        onToggle(word.id, date)
                    }
                )
            }
        }
    }
}

struct WordRowView: View {
    let word: Word
    let date: Date
    @ObservedObject var diaryManager: DiaryManager
    let isExpanded: Bool
    let onToggle: () -> Void
    
    // Modelden notu oku
    private var savedText: String {
        diaryManager.getNote(for: word.id, on: date) ?? ""
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            
            if isExpanded {
                if !savedText.isEmpty {
                    savedTextView
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.white.opacity(0.5))
    }
    
    private var mainRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(formatDay(date))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(4)
                .onTapGesture {
                    onToggle()
                }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(word.word)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if let phonetic = word.phonetic {
                    Text(phonetic)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onTapGesture {
                onToggle()
            }
            
            Spacer()
            
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20, height: 20)
                .onTapGesture {
                    onToggle()
                }
        }
        .padding(.vertical, 8)
    }
    
    private var savedTextView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 8)
            
            Text(savedText)
                .font(.body)
                .foregroundColor(.primary)
                .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Boş gesture - event'in yukarı yayılmasını engeller
        }
    }
    
    private func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

#Preview {
    DiaryView()
        .environmentObject(UserManager())
}
