//
//  SettingsView.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) var dismiss
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAlert = false
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    NavigationLink(destination: UserAgreementView()) {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("User Agreement")
                        }
                    }
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
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
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
}

struct UserAgreementView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("User Agreement")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("""
                By using Vocability, you agree to the following terms and conditions:
                
                1. You will use the app for educational purposes only.
                2. You are responsible for maintaining the confidentiality of your account.
                3. We reserve the right to modify these terms at any time.
                4. Premium features require a subscription.
                
                For questions, please contact support.
                """)
                .font(.body)
            }
            .padding()
        }
        .navigationTitle("User Agreement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environmentObject(UserManager())
}
