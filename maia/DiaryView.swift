//
//  DiaryView.swift
//  maia
//
//  Created by Mehmet Akdemir on 22.01.2026.
//

import SwiftUI

/// Günlük örnek cümle / not girişi; uyarı yok, sadece kırpma.
/// Not: `axis: .vertical` TextField içerde UITextView kullanır ve `Binding` setter'ını her güncellemede
/// güvenilir çağırmaz; sınır `onChange` ile uygulanır.
private enum DiaryTextLimits {
    static let maxExampleCharacters = 200

    static func clamped(_ text: String) -> String {
        String(text.prefix(maxExampleCharacters))
    }
}

struct DiaryView: View {
    @EnvironmentObject var diaryManager: DiaryManager
    @EnvironmentObject var userManager: UserManager
    @State private var expandedWordIds: Set<UUID> = []
    @State private var groupedDays: [Date: [Date]] = [:]
    @State private var navigationPath = NavigationPath()
    @State private var entriesUpdateTask: Task<Void, Never>?
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale.current
        return formatter
    }()

    private static let monthCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul") ?? .current
        return cal
    }()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            let sortedMonths = groupedDays.keys.sorted(by: >)
            ZStack {
                GlassSceneBackground()
                VStack(spacing: 0) {
                    if diaryManager.shouldShowCloudSyncBanner,
                       let syncMsg = diaryManager.cloudSyncUserMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(syncMsg)
                                .font(.footnote)
                                .foregroundColor(AppColors.glassCardBody)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button {
                                diaryManager.clearCloudSyncUserMessage()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.body)
                                    .foregroundColor(AppColors.glassCardMuted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Dismiss"))
                        }
                        .padding(12)
                        .background {
                            Group {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            }
                            .glassMaterialIgnoresSystemColorScheme()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                if sortedMonths.isEmpty {
                    ScrollView {
                        VStack(spacing: 20) {
                            Text("No Diary Entries Yet")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("Complete quizzes to start building your vocabulary diary!")
                                .font(.body)
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    }
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
                }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { wordId in
                if let word = word(for: wordId) {
                    QuizView(word: word)
                }
            }
        }
        .onAppear {
            if !diaryManager.hasSyncableDiaryContent {
                diaryManager.clearCloudSyncUserMessage()
            }
            updateGroupedDays()
        }
        .onChange(of: diaryManager.entries) { _, _ in
            entriesUpdateTask?.cancel()
            entriesUpdateTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                updateGroupedDays()
            }
        }
        .onDisappear {
            entriesUpdateTask?.cancel()
        }
    }
    
    private func updateGroupedDays() {
        // Sadece entry'leri olan günleri kullan - çok daha hızlı
        var grouped: [Date: [Date]] = [:]
        
        for entry in diaryManager.entries {
            guard !entry.words.isEmpty else { continue }
            let comps = Self.monthCalendar.dateComponents([.year, .month], from: entry.date)
            guard let monthKey = Self.monthCalendar.date(from: comps) else { continue }
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

    private func word(for wordId: UUID) -> Word? {
        diaryManager.entries.flatMap { $0.words }.first { $0.id == wordId }
    }
}

struct MonthSectionView: View {
    let monthKey: Date
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
            Text(Self.headerFormatter.string(from: monthKey).uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.95))
                .textCase(.uppercase)
        }
    }

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        formatter.locale = Locale.current
        return formatter
    }()
    
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
                .padding(.bottom, 6)
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
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showInputArea: Bool = false
    
    // Modelden notları oku
    private var savedNotes: [Note] {
        diaryManager.getNotes(for: word.id, on: date)
    }

    @ViewBuilder
    private var wordPhoneticAndTypeRow: some View {
        let phonetic = word.phonetic?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pos = word.partOfSpeech?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasPhonetic = !(phonetic?.isEmpty ?? true)
        let hasPOS = !(pos?.isEmpty ?? true)

        if hasPhonetic || hasPOS {
            HStack(spacing: 6) {
                if hasPhonetic, let phonetic {
                    Text(phonetic)
                        .font(.caption)
                        .foregroundColor(AppColors.glassCardMuted)
                        .italic()
                }
                if hasPOS, let pos {
                    Text(pos)
                        .font(.caption)
                        .italic()
                        .foregroundColor(.black.opacity(0.78))
                }
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            
            // Kaydedilmiş notlar ve Input area (sadece expanded olduğunda)
            if isExpanded {
                Divider()
                    .background(AppColors.glassCardTitle.opacity(0.15))
                    .padding(.vertical, 8)

                expandedDefinitionSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Definition alanına dokunmak kartı kapatmasın.
                    }

                savedNotesView
                    .transition(.opacity.combined(with: .move(edge: .top)))

                // Input area: kullanıcı "+" ile açar (Cancel ile kapanır)
                if showInputArea {
                    inputArea
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .wordCardGlassBackground(cornerRadius: 20)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .onChange(of: isExpanded) { oldValue, newValue in
            if newValue {
                // Expanded olduğunda input'u temizle (yeni not için)
                inputText = ""
                isInputFocused = false
                showInputArea = false
            } else {
                // Kapanınca focus'u kaldır ve input area'yı gizle
                isInputFocused = false
                showInputArea = false
            }
        }
    }
    
    private var mainRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(formatDay(date))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.glassCardTitle)
                .frame(width: 36, height: 36)
                .background {
                    Group {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.thinMaterial)
                    }
                    .glassMaterialIgnoresSystemColorScheme()
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppColors.glassCardTitle.opacity(0.2), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(word.word)
                    .font(.body.weight(.semibold))
                    .glassCardWordTitle()

                wordPhoneticAndTypeRow
            }
            
            Spacer()

            PronounceButton(word: word.word, audioURL: word.pronunciationAudioURL, size: 40)
                .padding(.trailing, 4)

            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundColor(AppColors.glassCardMuted)
                .frame(width: 20, height: 20)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
    }

    /// Today kartıyla aynı tipografi: üst etiket + okunaklı gövde.
    private var expandedDefinitionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Definition")
                .glassCardSectionLabel()

            Text(word.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : word.definition)
                .font(.body.weight(.medium))
                .glassCardReadableBody()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var savedNotesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(AppColors.glassCardTitle.opacity(0.15))
                .padding(.vertical, 8)

            HStack {
                Text("My example sentences")
                    .glassCardSectionLabel()
                
                Spacer()
                
                Button(action: {
                    showInputArea = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isInputFocused = true
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(AppColors.primaryButtonGradient, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                        }
                        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add example sentence")
            }
            .padding(.bottom, 4)
            
            ForEach(savedNotes) { note in
                NoteRowView(
                    note: note,
                    word: word,
                    onEdit: { newText, markSuggestionApplied in
                        diaryManager.updateNote(note.id, text: newText, for: word.id, on: date, markSuggestionApplied: markSuggestionApplied)
                    },
                    onDelete: {
                        diaryManager.deleteNote(note.id, for: word.id, on: date)
                    }
                )
                .padding(.bottom, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Event'in yukarı yayılmasını engelle
        }
    }
    
    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(AppColors.glassCardTitle.opacity(0.15))
                .padding(.vertical, 8)

            TextField("Add a note or example...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .lineLimit(3...6)
                .onChange(of: inputText) { _, newValue in
                    if newValue.count > DiaryTextLimits.maxExampleCharacters {
                        inputText = DiaryTextLimits.clamped(newValue)
                    }
                }
            
            HStack(spacing: 10) {
                Button(action: {
                    saveInput()
                }) {
                    Text("Save")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppColors.primaryButtonGradient)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain) // Gesture conflict'i önlemek için
                
                Button(action: {
                    discardInput()
                }) {
                    Text("Cancel")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppColors.glassCardTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            Group {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.thinMaterial)
                            }
                            .glassMaterialIgnoresSystemColorScheme()
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            // Event'in yukarı yayılmasını engelle
        }
    }
    
    private func saveInput() {
        let trimmedInput = DiaryTextLimits.clamped(
            inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !trimmedInput.isEmpty else {
            print("⚠️ Boş not kaydedilemez")
            return
        }
        
        print("💾 Not kaydediliyor: \(trimmedInput.prefix(50))...")
        // Firestore'a kaydet (DiaryManager içinde hem local hem Firestore'a kaydediyor)
        diaryManager.addNote(trimmedInput, for: word.id, on: date)
        inputText = ""
        isInputFocused = false
        showInputArea = false
        print("✅ Not kaydedildi")
    }
    
    private func discardInput() {
        inputText = ""
        isInputFocused = false
        showInputArea = false
    }
    
    private func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

struct NoteRowView: View {
    let note: Note
    let word: Word
    /// İkinci parametre: "Use this example" ile öneri metni uygulandığında true (Suggestion kalıcı olarak kapanır).
    let onEdit: (String, Bool) -> Void
    let onDelete: () -> Void
    
    private let exampleGenerator = ExampleGenerator()
    
    @State private var isEditing = false
    @State private var editedText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var dragOffset: CGFloat = 0
    @State private var isSuggesting = false
    /// Gemini önerisi; kullanıcı cümlesinin altında, soluk gösterilir (not metnini değiştirmez).
    @State private var aiSuggestionText: String?
    
    private let buttonWidth: CGFloat = 120 // Kalem + çöp butonlarının toplam genişliği
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                // Edit mode
                TextField("Edit note...", text: $editedText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .lineLimit(2...4)
                    .onChange(of: editedText) { _, newValue in
                        if newValue.count > DiaryTextLimits.maxExampleCharacters {
                            editedText = DiaryTextLimits.clamped(newValue)
                        }
                    }
                
                HStack(spacing: 10) {
                    Button(action: {
                        saveEdit()
                    }) {
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(AppColors.primaryButtonGradient)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {
                        cancelEdit()
                    }) {
                        Text("Cancel")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(AppColors.glassCardTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background {
                                Group {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.thinMaterial)
                                }
                                .glassMaterialIgnoresSystemColorScheme()
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.6)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            } else {
                // Display mode with swipe-to-reveal
                ZStack(alignment: .trailing) {
                    // Action buttons (background) - sağda, cümle kaydırıldıkça görünür
                    HStack(spacing: 0) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                            startEdit()
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 60)
                                .frame(maxHeight: .infinity)
                                .background(Color(red: 45/255, green: 52/255, blue: 58/255))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                dragOffset = 0
                            }
                            onDelete()
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 60)
                                .frame(maxHeight: .infinity)
                                .background(AppColors.MahoganyRed)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: buttonWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .offset(x: buttonWidth + dragOffset)
                    
                    // Content (foreground) — buble yok; Today ile aynı bullet + satır aralığı
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("•")
                                .font(.body.weight(.bold))
                                .foregroundColor(AppColors.glassCardBody)
                                .frame(width: 14, alignment: .leading)
                                .padding(.top, 1)

                            Text(note.text)
                                .font(.body.weight(.medium))
                                .foregroundColor(AppColors.glassCardBody)
                                .lineSpacing(3)
                                .shadow(color: Color.black.opacity(0.08), radius: 1, x: 0, y: 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)

                            if !note.suggestionApplyUsed {
                                Button(action: {
                                    Task { await runSuggestion() }
                                }) {
                                    Group {
                                        if isSuggesting {
                                            ProgressView()
                                                .scaleEffect(0.75)
                                        } else {
                                            VStack(spacing: 2) {
                                                Image(systemName: "lightbulb.fill")
                                                    .font(.system(size: 14))
                                                Text("Suggestion")
                                                    .font(.caption2)
                                                    .fontWeight(.medium)
                                            }
                                        }
                                    }
                                    .frame(width: 64)
                                    .foregroundColor(AppColors.primaryButton)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSuggesting || note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }

                        if let suggestion = aiSuggestionText {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("•")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.55))
                                        .frame(width: 14, alignment: .leading)
                                        .padding(.top, 1)

                                    Text(suggestion)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(AppColors.secondaryText.opacity(0.72))
                                        .italic()
                                        .lineSpacing(3)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                HStack(spacing: 8) {
                                    Button(action: applySuggestion) {
                                        Text("Use this example")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .frame(maxWidth: .infinity, minHeight: 36)
                                            .background(AppColors.primaryButtonGradient)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: discardSuggestion) {
                                        Text("Discard")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                            .frame(maxWidth: .infinity, minHeight: 36)
                                            .background(Color.gray.opacity(0.18))
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newOffset = value.translation.width
                                // Sadece sola kaydırmaya izin ver
                                if newOffset < 0 {
                                    dragOffset = max(newOffset, -buttonWidth)
                                } else if dragOffset < 0 {
                                    // Sağa kaydırma sadece swipe açıkken
                                    dragOffset = min(newOffset + dragOffset, 0)
                                }
                            }
                            .onEnded { value in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    if value.translation.width < -buttonWidth / 2 || dragOffset < -buttonWidth / 2 {
                                        // Swipe açık kal
                                        dragOffset = -buttonWidth
                                    } else {
                                        // Swipe kapan
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
                }
                .clipped()
            }
        }
        .onAppear {
            editedText = note.text
        }
        .onChange(of: note.text) { _, _ in
            aiSuggestionText = nil
        }
        .onChange(of: isEditing) { oldValue, newValue in
            if newValue {
                // Edit moduna geçince swipe'ı kapat
                withAnimation {
                    dragOffset = 0
                }
            }
        }
    }
    
    private func startEdit() {
        editedText = note.text
        isEditing = true
        // Focus'u biraz gecikmeyle ayarla (SwiftUI animasyon sorunu için)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func cancelEdit() {
        editedText = note.text
        isEditing = false
        isTextFieldFocused = false
    }
    
    private func saveEdit() {
        let trimmedText = DiaryTextLimits.clamped(
            editedText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !trimmedText.isEmpty else {
            cancelEdit()
            return
        }
        
        onEdit(trimmedText, false)
        isEditing = false
        isTextFieldFocused = false
    }
    
    private func runSuggestion() async {
        isSuggesting = true
        defer { isSuggesting = false }
        do {
            let corrected = try await exampleGenerator.suggestDiarySentenceImprovement(
                for: word,
                userSentence: note.text
            )
            await MainActor.run {
                aiSuggestionText = corrected
            }
        } catch {
            print("Suggestion error: \(error.localizedDescription)")
        }
    }
    
    private func applySuggestion() {
        guard let s = aiSuggestionText?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        onEdit(DiaryTextLimits.clamped(s), true)
        aiSuggestionText = nil
    }
    
    private func discardSuggestion() {
        aiSuggestionText = nil
    }
}

#Preview {
    DiaryView()
        .environmentObject(UserManager())
}
