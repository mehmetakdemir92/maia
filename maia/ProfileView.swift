//
//  ProfileView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI
import GoogleSignIn
import UIKit
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var badgeManager: BadgeManager
    @EnvironmentObject var diaryManager: DiaryManager
    @EnvironmentObject var statsManager: StatsManager
    @EnvironmentObject var streakManager: StreakManager
    @State private var showingSignIn = false
    @State private var showingSignUp = false
    @State private var showingSettings = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingEditNameSheet = false
    @State private var isUploadingProfilePhoto = false
    @State private var profilePhotoError: String?
    @State private var showingProfilePhotoError = false

    private var diaryWordCountComputed: Int {
        diaryManager.entries.reduce(0) { $0 + $1.words.count }
    }

    /// Rank için kullanılacak gerçek öğrenilen kelime sayısı (benzersiz word id).
    private var uniqueLearnedWordCountForRank: Int {
        let uniqueIds = Set(diaryManager.entries.flatMap { $0.words.map(\.id) })
        return uniqueIds.count
    }

    private var diaryWordCount: Int {
        statsManager.displayedWordsCount(diaryComputed: diaryWordCountComputed)
    }

    private var exampleSentencesCountComputed: Int {
        diaryManager.entries.reduce(0) { sum, entry in
            sum + entry.notesByWordId.values.reduce(0) { $0 + $1.count }
        }
    }

    private var exampleSentencesCount: Int {
        statsManager.displayedExampleSentencesCount(diaryComputed: exampleSentencesCountComputed)
    }

    private var quizAchievementPercent: String {
        statsManager.displayedQuizAchievementPercent()
    }

    private let cefrOrder: [String] = ["A1", "A2", "B1", "B2", "C1", "C2"]

    /// Diary'de quizlenen benzersiz kelimeleri CEFR seviyesine göre sayar.
    private var learnedWordsByLevel: [String: Int] {
        var latestWordById: [UUID: Word] = [:]
        for entry in diaryManager.entries {
            for word in entry.words {
                latestWordById[word.id] = word
            }
        }

        var counts: [String: Int] = Dictionary(uniqueKeysWithValues: cefrOrder.map { ($0, 0) })
        for word in latestWordById.values {
            guard let rawLevel = word.cefrLevel?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                  cefrOrder.contains(rawLevel) else { continue }
            counts[rawLevel, default: 0] += 1
        }
        return counts
    }

    private var totalLearnedCefrWords: Int {
        learnedWordsByLevel.values.reduce(0, +)
    }

    private var strongestCefrLevel: String? {
        let sorted = cefrOrder
            .map { ($0, learnedWordsByLevel[$0, default: 0]) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return cefrOrder.firstIndex(of: lhs.0)! < cefrOrder.firstIndex(of: rhs.0)!
                }
                return lhs.1 > rhs.1
            }
        guard let top = sorted.first, top.1 > 0 else { return nil }
        return top.0
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassSceneBackground()
                ScrollView {
                if userManager.isSignedIn {
                    // Signed in view
                    VStack(alignment: .leading, spacing: 32) {
                        // Profile header - ortalanmış foto + isim
                        VStack(spacing: 12) {
                            ZStack(alignment: .bottomTrailing) {
                                ZStack {
                                    Circle()
                                        .fill(AppColors.primaryButton.opacity(0.2))
                                        .frame(width: 110, height: 110)

                                    if let imageURL = userManager.profileImageURL {
                                        AsyncImage(url: URL(string: imageURL)) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 34))
                                                .foregroundColor(AppColors.primaryButton)
                                        }
                                        .clipShape(Circle())
                                        .frame(width: 110, height: 110)
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 34))
                                            .foregroundColor(AppColors.primaryButton)
                                    }
                                }

                                Button(action: {
                                    showingPhotoPicker = true
                                }) {
                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundColor(AppColors.primaryButton)
                                        .background(Circle().fill(Color.white))
                                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                                }
                                .offset(x: 4, y: 4)
                            }

                            HStack(spacing: 8) {
                                Text(userManager.userName)
                                    .font(.title2.weight(.bold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                Button {
                                    showingEditNameSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.9))
                                        .padding(6)
                                        .background(Color.white.opacity(0.16), in: Circle())
                                }
                                .accessibilityLabel("Edit Name")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        
                        
                        // Stats: Hero + supporting cards; Free kullanıcıda bazı metrikler kilitli preview.
                        VStack(alignment: .leading, spacing: 12) {
                            HeroStatCard(
                                value: "\(streakManager.currentStreak)",
                                titleKey: "Current Streak",
                                subtitleKey: "days",
                                iconName: "flame.fill"
                            )
                            .padding(.horizontal)

                            HeroStatCard(
                                value: "\(diaryWordCount)",
                                titleKey: "Words",
                                subtitleKey: "learned",
                                iconName: "book.fill"
                            )
                            .padding(.horizontal)

                            MiniRankCard(
                                rank: statsManager.rankDisplay,
                                titleKey: "Streak Rank",
                                isLocked: false
                            )
                            .padding(.horizontal)

                            MiniRankCard(
                                rank: statsManager.wordRankDisplay,
                                titleKey: "Word Rank",
                                isLocked: false
                            )
                            .padding(.horizontal)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                CompactStatCard(
                                    value: "\(exampleSentencesCount)",
                                    titleKey: "Example Sentences",
                                    isLocked: false
                                )
                                CompactStatCard(
                                    value: quizAchievementPercent,
                                    titleKey: "Quiz Achievement",
                                    isLocked: !userManager.isPremium
                                )
                                CompactStatCard(
                                    value: "\(streakManager.maxStreak)",
                                    titleKey: "Max. Streak",
                                    isLocked: !userManager.isPremium
                                )
                                CompactStatCard(
                                    value: "\(statsManager.totalPerfectQuizzes)",
                                    titleKey: "Perfect Quizzes",
                                    isLocked: false
                                )
                            }
                            .padding(.horizontal)

                            CEFRCoverageCard(
                                levels: cefrOrder,
                                countsByLevel: learnedWordsByLevel,
                                totalWords: totalLearnedCefrWords,
                                strongestLevel: strongestCefrLevel
                            )
                            .padding(.horizontal)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical)
                } else {
                    // Not signed in view
                    VStack(spacing: 24) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.gray)
                        
                        Text("Sign in to view your profile")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        
                        VStack(spacing: 12) {
                            // Google Sign-In Button - Google'ın resmi buton stili
                            GoogleSignInButton(action: {
                                Task {
                                    do {
                                        try await userManager.signInWithGoogle()
                                    } catch {
                                        print("Google Sign-In Error: \(error.localizedDescription)")
                                    }
                                }
                            })
                            
                            Button(action: {
                                showingSignIn = true
                            }) {
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppColors.primaryButtonGradient)
                                    .cornerRadius(10)
                            }
                            
                            Button(action: {
                                showingSignUp = true
                            }) {
                                Text("Sign Up")
                                    .font(.headline)
                                                .foregroundColor(AppColors.primaryButton)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppColors.primaryButton.opacity(0.1))
                                    .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if userManager.isSignedIn {
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.white.opacity(0.95))
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSignIn) {
                SignInView()
            }
            .sheet(isPresented: $showingSignUp) {
                SignUpView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingEditNameSheet) {
                EditDisplayNameView()
                    .environmentObject(userManager)
            }
            .onAppear {
                if userManager.isSignedIn {
                    statsManager.updateScoreFrom(
                        streak: streakManager.currentStreak,
                        maxStreak: streakManager.maxStreak,
                        wordCount: uniqueLearnedWordCountForRank
                    )
                }
            }
            .onChange(of: streakManager.currentStreak) { _, _ in
                if userManager.isSignedIn {
                    statsManager.updateScoreFrom(
                        streak: streakManager.currentStreak,
                        maxStreak: streakManager.maxStreak,
                        wordCount: uniqueLearnedWordCountForRank
                    )
                }
            }
            .onChange(of: diaryManager.entries.count) { _, _ in
                if userManager.isSignedIn {
                    statsManager.updateScoreFrom(
                        streak: streakManager.currentStreak,
                        maxStreak: streakManager.maxStreak,
                        wordCount: uniqueLearnedWordCountForRank
                    )
                }
            }
            .overlay {
                if showingPhotoPicker {
                    ProfilePhotoOptionsOverlay(
                        isPresented: $showingPhotoPicker,
                        selectedPhotoItem: $selectedPhotoItem,
                        isUploading: isUploadingProfilePhoto
                    )
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem = newItem else { return }
                showingPhotoPicker = false
                Task {
                    await MainActor.run { isUploadingProfilePhoto = true }
                    do {
                        guard let data = try await newItem.loadTransferable(type: Data.self),
                              let uiImage = UIImage(data: data),
                              let jpegData = uiImage.jpegData(compressionQuality: 0.7) else {
                            await MainActor.run {
                                profilePhotoError = "Could not load image"
                                showingProfilePhotoError = true
                                isUploadingProfilePhoto = false
                            }
                            return
                        }
                        try await userManager.uploadProfilePhoto(imageData: jpegData)
                        await MainActor.run {
                            selectedPhotoItem = nil
                            isUploadingProfilePhoto = false
                        }
                    } catch {
                        await MainActor.run {
                            profilePhotoError = error.localizedDescription
                            showingProfilePhotoError = true
                            isUploadingProfilePhoto = false
                        }
                    }
                }
            }
            .alert("Profile Photo Error", isPresented: $showingProfilePhotoError) {
                Button("OK", role: .cancel) {
                    profilePhotoError = nil
                }
            } message: {
                Text(profilePhotoError ?? "An error occurred")
            }
        }
    }
}

struct EditDisplayNameView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Edit Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        Task {
                            isSaving = true
                            do {
                                try await userManager.updateDisplayName(name)
                                isSaving = false
                                dismiss()
                            } catch {
                                isSaving = false
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                name = userManager.userName
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }
}

struct SignInView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    SecureField("Password", text: $password)
                }
                
                // Google Sign-In Button
                Button(action: {
                    Task {
                        isLoading = true
                        do {
                            try await userManager.signInWithGoogle()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                        isLoading = false
                    }
                }) {
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                        Text("Continue with Google")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoading)
                
                Button(action: {
                    Task {
                        isLoading = true
                        do {
                            try await userManager.signIn(email: email, password: password)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                        isLoading = false
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                        Text("Sign In")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(email.isEmpty || password.isEmpty || isLoading)
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }
}

struct SignUpView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    SecureField("Password", text: $password)
                }
                
                // Google Sign-In Button
                Button(action: {
                    Task {
                        isLoading = true
                        do {
                            try await userManager.signInWithGoogle()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                        isLoading = false
                    }
                }) {
                    HStack {
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                        Text("Continue with Google")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isLoading)
                
                Button(action: {
                    Task {
                        isLoading = true
                        do {
                            try await userManager.signUp(email: email, password: password, name: name)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                        isLoading = false
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        }
                        Text("Sign Up")
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(name.isEmpty || email.isEmpty || password.isEmpty || isLoading)
            }
            .navigationTitle("Sign Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }
}

// Google Sign-In Button - Google'ın resmi buton tasarımını taklit eden SwiftUI bileşeni
struct GoogleSignInButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Beyaz arka plan - Google'ın resmi buton stili
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                
                // Google logosu - resmi renklerle basitleştirilmiş görünüm
                ZStack {
                    // Google'ın renkli logo parçaları (basitleştirilmiş)
                    // Mavi kısım
                    Circle()
                        .trim(from: 0.75, to: 1.0)
                        .stroke(Color(red: 66/255, green: 133/255, blue: 244/255), lineWidth: 4.5)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                    
                    // Kırmızı kısım
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(Color(red: 234/255, green: 67/255, blue: 53/255), lineWidth: 4.5)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                    
                    // Sarı kısım
                    Circle()
                        .trim(from: 0.25, to: 0.5)
                        .stroke(Color(red: 251/255, green: 188/255, blue: 5/255), lineWidth: 4.5)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                    
                    // Yeşil kısım
                    Circle()
                        .trim(from: 0.5, to: 0.75)
                        .stroke(Color(red: 52/255, green: 168/255, blue: 83/255), lineWidth: 4.5)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                    
                    // İç beyaz daire (G harfinin arka planı)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .offset(x: 6, y: 0)
                    
                    // G harfi (mavi)
                    Text("G")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 66/255, green: 133/255, blue: 244/255))
                        .offset(x: 6, y: 0)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Ekranın ortasında beyaz kart: Galeriden seç / İptal
struct ProfilePhotoOptionsOverlay: View {
    @Binding var isPresented: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    var isUploading: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isUploading { isPresented = false }
                }
            
            VStack(spacing: 0) {
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("Choose from Library")
                    }
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .disabled(isUploading)
                
                Divider()
                    .padding(.horizontal, 16)
                
                Button {
                    isPresented = false
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(AppColors.primaryButton)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .disabled(isUploading)
            }
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 40)
        }
    }
}

/// SwiftUI `Material` yerine `UIBlurEffect(.systemThickMaterial)` — arka planı belirgin şekilde buğular.
private struct SystemThickBlurBackground: UIViewRepresentable {
    var cornerRadius: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        view.backgroundColor = .clear
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.layer.cornerRadius = cornerRadius
    }
}

// Hero stat kartı — üstte tek metrik (streak odaklı)
struct HeroStatCard: View {
    let value: String
    var titleKey: LocalizedStringKey
    var subtitleKey: LocalizedStringKey
    var iconName: String = "flame.fill"

    private var valueFontSize: CGFloat {
        let n = value.count
        if n > 5 { return 42 }
        if n > 3 { return 48 }
        return 54
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(titleKey)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(AppColors.glassCardTitle)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value)
                        .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                        .foregroundColor(AppColors.statValueColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)

                    Text(subtitleKey)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.glassCardMuted)
                }
            }

            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppColors.primaryButtonGradient)
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .center)
        .statCardGlassBackground(cornerRadius: 16)
    }
}

// Supporting stat kartı — küçük metrikler (kilitli görünüm destekli)
struct CompactStatCard: View {
    let value: String
    var titleKey: LocalizedStringKey
    let isLocked: Bool

    var body: some View {
        VStack(spacing: 6) {
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.glassCardMuted)
            }

            Text(isLocked ? "—" : value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(isLocked ? AnyShapeStyle(AppColors.glassCardMuted.opacity(0.7)) : AnyShapeStyle(AppColors.statValueColor))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)

            Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.glassCardTitle)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 110)
        .statCardGlassBackground(cornerRadius: 16)
    }
}

// Alt satır rank kartı
struct MiniRankCard: View {
    let rank: String
    var titleKey: LocalizedStringKey = "Streak Rank"
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(AppColors.primaryButtonGradient)
            Text(titleKey)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.glassCardMuted)
            Spacer()
            if isLocked {
                Image(systemName: "lock.fill")
                    .foregroundColor(AppColors.glassCardMuted)
            } else {
                Text(rank)
                    .font(.headline.weight(.bold))
                    .foregroundColor(AppColors.statValueColor)
                    .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .statCardGlassBackground(cornerRadius: 14)
    }
}

/// CEFR seviyelerine göre öğrenilen kelime dağılımı (motive edici ilerleme görünümü).
struct CEFRCoverageCard: View {
    let levels: [String]
    let countsByLevel: [String: Int]
    let totalWords: Int
    let strongestLevel: String?

    private var maxCount: Int {
        max(1, countsByLevel.values.max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CEFR Journey")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(AppColors.glassCardTitle)
                    Text(totalWords == 0 ? "Start with your first word today." : "\(totalWords) learned words")
                        .font(.subheadline)
                        .foregroundColor(AppColors.glassCardMuted)
                }
                Spacer()
                if let strongestLevel {
                    Text(strongestLevel)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(AppColors.statValueColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryButton.opacity(0.14))
                        )
                }
            }

            VStack(spacing: 9) {
                ForEach(levels, id: \.self) { level in
                    let count = countsByLevel[level, default: 0]
                    HStack(spacing: 10) {
                        Text(level)
                            .font(.caption.weight(.bold))
                            .foregroundColor(AppColors.glassCardTitle)
                            .frame(width: 26, alignment: .leading)

                        GeometryReader { geo in
                            let width = geo.size.width * CGFloat(count) / CGFloat(maxCount)
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppColors.glassCardMuted.opacity(0.18))
                                Capsule()
                                    .fill(AppColors.primaryButtonGradient)
                                    .frame(width: max(6, width))
                                    .opacity(count == 0 ? 0.25 : 1.0)
                            }
                        }
                        .frame(height: 10)

                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.glassCardMuted)
                            .frame(width: 26, alignment: .trailing)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .statCardGlassBackground(cornerRadius: 14)
    }
}

#Preview {
    ProfileView()
        .environmentObject(UserManager())
        .environmentObject(BadgeManager())
        .environmentObject(DiaryManager())
        .environmentObject(StatsManager())
        .environmentObject(StreakManager())
}
