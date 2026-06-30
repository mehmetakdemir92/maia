//
//  AuthEntryView.swift
//  maia
//

import SwiftUI

struct AuthEntryView: View {
    private enum AuthMode {
        case none
        case signIn
        case signUp
    }

    @EnvironmentObject var userManager: UserManager
    @State private var authMode: AuthMode = .none
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isAuthLoading = false
    @State private var isGoogleLoading = false
    @State private var isAppleLoading = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var selectedLegalDocument: LegalDocumentType?
    
    var body: some View {
        NavigationStack {
            ZStack {
                GlassSceneBackground(isAnimated: true)

                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    VStack(spacing: 10) {
                        Text("Maia")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

                        Text("Build your daily English habit")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white.opacity(0.92))
                    }
                    .padding(.horizontal)

                    if authMode == .none {
                        VStack(spacing: 12) {
                            Button {
                                beginEmailForm(.signUp)
                            } label: {
                                Text("Create account")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                .background(AppColors.primaryButtonGradient)
                                    .cornerRadius(12)
                            }

                            Button {
                                beginEmailForm(.signIn)
                            } label: {
                                Text("Log in")
                                    .font(.headline)
                                    .foregroundColor(AppColors.glassCardTitle)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background {
                                        Group {
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(.thinMaterial)
                                        }
                                        .glassMaterialIgnoresSystemColorScheme()
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8)
                                    }
                            }
                        }
                    } else {
                        formCard
                    }

                    if authMode == .none {
                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(Color.white.opacity(0.45))
                                .frame(height: 1)
                            Text(String(localized: "or"))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.88))
                            Rectangle()
                                .fill(Color.white.opacity(0.45))
                                .frame(height: 1)
                        }
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                    }

                    VStack(spacing: 12) {
                        Button {
                            Task {
                                isAppleLoading = true
                                AppAnalytics.shared.log(AppAnalyticsEventName.signInStarted, params: ["method": "apple"])
                                do {
                                    try await userManager.signInWithApple()
                                } catch {
                                    if !isUserCancelledSignIn(error) {
                                        errorMessage = error.localizedDescription
                                        showingError = true
                                    }
                                }
                                isAppleLoading = false
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                                if isAppleLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: "apple.logo")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.black)

                                        Text(String(localized: "Sign in with Apple"))
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(.black)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .disabled(isAppleLoading || isGoogleLoading)
                        .accessibilityLabel(String(localized: "Continue with Apple"))

                        Button {
                            Task {
                                isGoogleLoading = true
                                AppAnalytics.shared.log(AppAnalyticsEventName.signInStarted, params: ["method": "google"])
                                do {
                                    try await userManager.signInWithGoogle()
                                } catch {
                                    if !isUserCancelledSignIn(error) {
                                        errorMessage = error.localizedDescription
                                        showingError = true
                                    }
                                }
                                isGoogleLoading = false
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)

                                if isGoogleLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 60 / 255, green: 64 / 255, blue: 67 / 255)))
                                } else {
                                    HStack(spacing: 10) {
                                        Image("GoogleGLogo")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 18, height: 18)

                                        Text("Sign in with Google")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundColor(Color(red: 60 / 255, green: 64 / 255, blue: 67 / 255))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .disabled(isGoogleLoading || isAppleLoading)
                        .accessibilityLabel(String(localized: "Sign in with Google"))
                    }

                    Spacer()

                    VStack(spacing: 6) {
                        Text(String(localized: "By continuing, you agree to our Terms of Use and Privacy Policy."))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.86))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 14) {
                            Button(String(localized: "Terms of Use")) {
                                selectedLegalDocument = .terms
                            }
                            .buttonStyle(.plain)

                            Button(String(localized: "Privacy Policy")) {
                                selectedLegalDocument = .privacy
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption.weight(.semibold))
                        .tint(.white)
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
            }
            .alert("Sign in error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .onAppear {
                AppAnalytics.shared.log(AppAnalyticsEventName.onboardingStarted)
            }
            .sheet(item: $selectedLegalDocument) { document in
                NavigationStack {
                    LegalDocumentView(document: document)
                }
            }
            .navigationBarHidden(true)
        }
    }

    private func beginEmailForm(_ mode: AuthMode) {
        email = ""
        password = ""
        confirmPassword = ""
        authMode = mode
    }

    private var formCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Back") {
                    authMode = .none
                    email = ""
                    password = ""
                    confirmPassword = ""
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.primaryButton)
                .underline()
                Spacer()
            }

            emailField

            passwordField

            if authMode == .signUp {
                confirmPasswordField
            }

            if authMode == .signIn {
                Button {
                    userManager.setRememberMeEnabled(!userManager.rememberMeEnabled)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: userManager.rememberMeEnabled ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(userManager.rememberMeEnabled ? AppColors.primaryButton : AppColors.glassCardTitle.opacity(0.55))
                        Text("Remember Me")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.glassCardTitle.opacity(0.72))
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            Button {
                Task {
                    isAuthLoading = true
                    if authMode == .signUp && password != confirmPassword {
                        errorMessage = String(localized: "Passwords don't match")
                        showingError = true
                        isAuthLoading = false
                        return
                    }
                    do {
                        if authMode == .signIn {
                            AppAnalytics.shared.log(AppAnalyticsEventName.signInStarted, params: ["method": "email"])
                            try await userManager.signIn(email: email, password: password)
                        } else {
                            AppAnalytics.shared.log(AppAnalyticsEventName.signUpStarted, params: ["method": "email"])
                            try await userManager.signUp(email: email, password: password)
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                        showingError = true
                    }
                    isAuthLoading = false
                }
            } label: {
                HStack {
                    if isAuthLoading {
                        ProgressView().progressViewStyle(.circular)
                    }
                    Text(authMode == .signIn ? "Log in" : "Create account")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColors.primaryButtonGradient)
                .cornerRadius(10)
            }
            .disabled(
                isAuthLoading
                    || email.isEmpty
                    || password.isEmpty
                    || (authMode == .signUp && confirmPassword.isEmpty)
            )
        }
        .padding(20)
        .wordCardGlassBackground(cornerRadius: 22)
    }

    @ViewBuilder
    private var emailField: some View {
        let field = TextField(String(localized: "Email"), text: $email)
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .autocorrectionDisabled()
            .foregroundColor(AppColors.glassCardTitle)
            .tint(AppColors.primaryButton)
            .padding(12)
            .background {
                Group {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .glassMaterialIgnoresSystemColorScheme()
            }

        if authMode == .signUp {
            // New account: reduces saved-login suggestion (.username surfaces old email).
            field.textContentType(.emailAddress)
        } else {
            field.textContentType(.username)
        }
    }

    private var passwordField: some View {
        SecureField("Password", text: $password)
            .textContentType(authMode == .signUp ? .newPassword : .password)
            .foregroundColor(AppColors.glassCardTitle)
            .tint(AppColors.primaryButton)
            .padding(12)
            .background {
                Group {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .glassMaterialIgnoresSystemColorScheme()
            }
    }

    private var confirmPasswordField: some View {
        SecureField(String(localized: "Confirm password"), text: $confirmPassword)
            .textContentType(.newPassword)
            .foregroundColor(AppColors.glassCardTitle)
            .tint(AppColors.primaryButton)
            .padding(12)
            .background {
                Group {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .glassMaterialIgnoresSystemColorScheme()
            }
    }

    private func isUserCancelledSignIn(_ error: Error) -> Bool {
        let nsError = error as NSError
        let domain = nsError.domain.lowercased()
        let message = nsError.localizedDescription.lowercased()

        // Covers Apple / Google cancel flows and generic localized cancel wording.
        return domain.contains("authorization") && nsError.code == 1001
            || domain.contains("gidsignin") && nsError.code == -5
            || domain.contains("google") && message.contains("canceled")
            || message.contains("canceled")
            || message.contains("cancelled")
            || message.contains("iptal")
    }
}

#Preview {
    AuthEntryView()
        .environmentObject(UserManager())
}
