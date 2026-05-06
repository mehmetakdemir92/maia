//
//  ProfileView.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var badgeManager: BadgeManager
    @State private var showingSignIn = false
    @State private var showingSignUp = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                if userManager.isSignedIn {
                    // Signed in view
                    VStack(alignment: .leading, spacing: 24) {
                        // Profile header - Sol üstte küçük fotoğraf, yanında isim
                        HStack(alignment: .top, spacing: 24) {
                            // Profile image - Küçük, sol üstte
                            ZStack {
                                Circle()
                                    .fill(AppColors.primaryButton.opacity(0.2))
                                    .frame(width: 100, height: 100)
                                
                                if let imageURL = userManager.profileImageURL {
                                    AsyncImage(url: URL(string: imageURL)) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 30))
                                            .foregroundColor(AppColors.primaryButton)
                                    }
                                    .clipShape(Circle())
                                    .frame(width: 100, height: 100)
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(AppColors.primaryButton)
                                }
                            }
                            
                            // İsim ve followers/following
                            VStack(alignment: .leading, spacing: 16) {
                                Text(userManager.userName)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                // Followers/Following - İsim altında
                                HStack(spacing: 20) {
                                    HStack(spacing: 8) {
                                        Text("\(userManager.followers)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text("Followers")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Text("\(userManager.following)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text("Following")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.top)
                        
                        // Badges section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Badges")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(badgeManager.badges.filter { $0.isUnlocked }) { badge in
                                        VStack {
                                            Image(systemName: badge.iconName)
                                                .font(.system(size: 30))
                                                .foregroundColor(AppColors.primaryButton)
                                            Text(badge.name)
                                                .font(.caption)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(width: 80)
                                        .padding()
                                        .background(AppColors.primaryButton.opacity(0.1))
                                        .cornerRadius(12)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        // Stats section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Stats")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Level")
                                    Spacer()
                                    Text("\(userManager.userLevel)")
                                        .fontWeight(.bold)
                                }
                                
                                Divider()
                                
                                HStack {
                                    Text("Premium")
                                    Spacer()
                                    Text(userManager.isPremium ? "Yes" : "No")
                                        .fontWeight(.bold)
                                        .foregroundColor(userManager.isPremium ? .green : .secondary)
                                }
                            }
                            .padding()
                            .background(AppColors.background)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
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
                            // Google Sign-In Button
                            Button(action: {
                                Task {
                                    do {
                                        try await userManager.signInWithGoogle()
                                    } catch {
                                        print("Google Sign-In Error: \(error.localizedDescription)")
                                    }
                                }
                            }) {
                                HStack {
                                    Image(systemName: "globe")
                                        .font(.system(size: 18))
                                    Text("Continue with Google")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .cornerRadius(10)
                            }
                            
                            Button(action: {
                                showingSignIn = true
                            }) {
                                Text("Sign In")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(AppColors.primaryButton)
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
            .background(AppColors.background)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if userManager.isSignedIn {
                        Button(action: {
                            showingSettings = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.primary)
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

#Preview {
    ProfileView()
        .environmentObject(UserManager())
        .environmentObject(BadgeManager())
}
