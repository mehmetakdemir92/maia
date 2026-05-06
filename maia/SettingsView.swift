//
//  SettingsView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var languageManager: AppLanguageManager
    @Environment(\.dismiss) var dismiss
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAlert = false
    @State private var showingPremiumPaywall = false
    @State private var isRestoringPurchases = false
    @State private var selectedLegalDocument: LegalDocumentType?
    private static let cefrStepLabels: [String] = [
        "A1", "A1+", "A2", "A2+", "B1", "B1+", "B2", "B2+", "C1", "C1+", "C2"
    ]
    
    private var displayName: String {
        userManager.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User" : userManager.userName
    }
    
    private var displayEmail: String {
        userManager.userEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No email" : userManager.userEmail
    }

    var body: some View {
        NavigationView {
            ZStack {
                GlassSceneBackground()
                List {
                if userManager.isSignedIn {
                    Section {
                        HStack(spacing: 12) {
                            profileAvatar
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayName)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Text(displayEmail)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section {
                    Picker(selection: Binding(
                        get: { languageManager.selectedOption },
                        set: { languageManager.setSelected($0) }
                    )) {
                        ForEach(AppLanguageOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text("Languages")
                                .foregroundColor(.white)
                        }
                    }
                } header: {
                    Text("Languages")
                        .foregroundColor(.white)
                } footer: {
                    Text("App language applies immediately. System follows your device language.")
                        .foregroundColor(.white.opacity(0.8))
                }

                Section {
                    Button {
                        selectedLegalDocument = .privacy
                    } label: {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                            Text(String(localized: "Privacy Policy"))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button {
                        selectedLegalDocument = .terms
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text(String(localized: "Terms of Use"))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)

                    Button {
                        selectedLegalDocument = .subscription
                    } label: {
                        HStack {
                            Image(systemName: "creditcard.fill")
                            Text(String(localized: "Subscription Terms"))
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                } header: {
                    Text(String(localized: "Legal"))
                        .foregroundColor(.white)
                }
                
                Section {
                    Button {
                        showingPremiumPaywall = true
                    } label: {
                        HStack {
                            Image(systemName: "crown.fill")
                            Text(userManager.isPremium ? "Premium" : "Get Premium")
                            Spacer()
                            if userManager.isPremium {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .foregroundColor(.primary)

                    Button {
                        Task { @MainActor in
                            isRestoringPurchases = true
                            try? await userManager.restorePurchases()
                            isRestoringPurchases = false
                        }
                    } label: {
                        HStack {
                            if isRestoringPurchases {
                                ProgressView()
                            }
                            Text("Restore purchases")
                        }
                    }
                    .disabled(isRestoringPurchases)
                } header: {
                    Text("Subscription")
                        .foregroundColor(.white)
                } footer: {
                    Text("Premium removes ads and unlocks word focus categories and AI example sentences.")
                        .foregroundColor(.white.opacity(0.8))
                }

                #if DEBUG
                Section {
                    Toggle(isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "debugPremiumOverride") },
                        set: { userManager.setDebugPremiumOverride($0) }
                    )) {
                        HStack {
                            Image(systemName: "ladybug.fill")
                            Text("Debug: force Premium")
                        }
                    }
                } footer: {
                    Text("Only in DEBUG builds. Mimics App Store subscription.")
                        .foregroundColor(.white.opacity(0.8))
                }
                #endif
                
                Section {
                    Picker(selection: Binding(
                        get: { userManager.userLevel },
                        set: { userManager.setUserLevel($0) }
                    )) {
                        ForEach(Array(Self.cefrStepLabels.enumerated()), id: \.offset) { index, level in
                            Text(level).tag(index + 1)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "chart.bar.fill")
                            Text("English level")
                                .foregroundColor(.white)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("English level")
                        .foregroundColor(.white)
                } footer: {
                    Text("Change your CEFR step anytime. This affects your learning difficulty.")
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Section {
                    Button(action: {
                        showingSignOutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square")
                            Text("Sign Out")
                        }
                        .foregroundColor(.red)
                    }
                    
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Freeze & Delete Account")
                        }
                        .foregroundColor(.red)
                    }
                }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.35), radius: 1, x: 0, y: 1)
                }
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    do {
                        try userManager.signOut()
                        dismiss()
                    } catch {
                        print("Sign out error: \(error.localizedDescription)")
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .sheet(isPresented: $showingPremiumPaywall) {
                PremiumPaywallView(placement: AppAnalyticsPlacement.settings)
                    .environmentObject(userManager)
            }
            .sheet(item: $selectedLegalDocument) { document in
                NavigationStack {
                    LegalDocumentView(document: document)
                }
            }
            .alert("Delete Account", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    // Handle account deletion
                    do {
                        try userManager.signOut()
                        dismiss()
                    } catch {
                        print("Sign out error: \(error.localizedDescription)")
                    }
                }
            } message: {
                Text("This action cannot be undone. Are you sure you want to delete your account?")
            }
        }
    }
    
    private var profileAvatar: some View {
        Group {
            if let imageURL = userManager.profileImageURL,
               let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Text(String(displayName.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .frame(width: 42, height: 42)
        .clipShape(Circle())
    }
}

struct UserAgreementView: View {
    var body: some View {
        ZStack {
            GlassSceneBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("User Agreement")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(String(localized: String.LocalizationValue(
"""
By using Maia, you agree to the following terms and conditions:

1. You will use the app for educational purposes only.
2. You are responsible for maintaining the confidentiality of your account.
3. We reserve the right to modify these terms at any time.
4. Premium features require a subscription.

For questions, please contact support.
"""
                    )))
                    .font(.body)
                }
                .padding()
            }
        }
        .navigationTitle("User Agreement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    SettingsView()
        .environmentObject(UserManager())
        .environmentObject(AppLanguageManager())
}
