//
//  UserManager.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import Foundation
import Combine
import StoreKit
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import GoogleSignIn
import UIKit

class UserManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userName: String = ""
    @Published var userEmail: String = ""
    @Published var profileImageURL: String? = nil
    @Published var followers: Int = 0
    @Published var following: Int = 0
    /// StoreKit subscription combined with DEBUG/TestFlight test override.
    @Published var isPremium: Bool = false
    @Published var userLevel: Int = 1 // 1-11 scale (CEFR + intermediate steps)
    @Published var registrationDate: Date = Date()
    @Published var selectedCategory: VocabularyCategory = .general
    @Published var requiresInitialSetup: Bool = false

    /// Active App Store subscription (excluding debug override).
    private(set) var subscriptionEntitlementActive: Bool = false

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private var storeKitUpdatesTask: Task<Void, Never>?

    private static let debugPremiumDefaultsKey = "debugPremiumOverride"
    private static let onboardingCompletedPrefix = "onboardingCompleted."
    private static let rememberMeDefaultsKey = "rememberMeEnabled"
    private static let signOutOnNextLaunchDefaultsKey = "signOutOnNextLaunch"
    private static let profilePhotoHiddenPrefix = "profilePhotoHidden."
    private static let legacyUserLevelDefaultsKey = "userLevel"
    private static let legacyCategoryDefaultsKey = "vocabularyCategory"
    private static let profileSettingsDoc = "profileSettings"

    private let db = Firestore.firestore()
    private var lastObservedAuthUID: String?
    private var currentAppleSignInNonce: String?
    private var pendingNewSignUpUID: String?
    @Published var rememberMeEnabled: Bool

    /// Clears local-only caches that were historically stored without scoping to Firebase UID.
    /// Without this, signing into a new account on the same device can inherit the previous user's streak/stats/diary.
    private static func clearPerAccountLocalCaches() {
        let defaults = UserDefaults.standard

        // Known keys (non-exhaustive but covers the main leak sources in this project)
        defaults.removeObject(forKey: "completedStreakDates")
        defaults.removeObject(forKey: "stats_totalQuizzesTaken")
        defaults.removeObject(forKey: "stats_totalCorrectAnswers")
        defaults.removeObject(forKey: "stats_totalQuestionsAnswered")
        defaults.removeObject(forKey: "diaryEntries")
        defaults.removeObject(forKey: "wordProgressMap")
        defaults.removeObject(forKey: "quizEvents")
        defaults.removeObject(forKey: "generatedExampleSentences")

        // Prefix-based keys (quiz attempts / global sentence de-duping)
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix("quizAttempts_")
                || key.hasPrefix("quizGlobalBlankSentences_")
                || key.hasPrefix("completedStreakDates.")
                || key.hasPrefix("stats_totalQuizzesTaken.")
                || key.hasPrefix("stats_totalCorrectAnswers.")
                || key.hasPrefix("stats_totalQuestionsAnswered.")
                || key.hasPrefix("diaryEntries.")
                || key.hasPrefix("wordProgressMap.")
                || key.hasPrefix("quizEvents.") {
                defaults.removeObject(forKey: key)
            }
        }

        Task { @MainActor in
            DailyWordUsageStore.shared.resetAll()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        if let storedRememberPreference = defaults.object(forKey: Self.rememberMeDefaultsKey) as? Bool {
            rememberMeEnabled = storedRememberPreference
        } else {
            rememberMeEnabled = true
            defaults.set(true, forKey: Self.rememberMeDefaultsKey)
        }

        if defaults.bool(forKey: Self.signOutOnNextLaunchDefaultsKey) {
            try? Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            defaults.set(false, forKey: Self.signOutOnNextLaunchDefaultsKey)
        }

        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.updateUserState(user: user)
            }
        }
        loadUserData()
        startListeningForSubscriptions()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        storeKitUpdatesTask?.cancel()
    }

    private func updateUserState(user: FirebaseAuth.User?) {
        if let user = user {
            isSignedIn = true
            userEmail = user.email ?? ""
            userName = user.displayName ?? userEmail.components(separatedBy: "@").first ?? "User"
            profileImageURL = resolvedProfileImageURL(for: user)
            registrationDate = user.metadata.creationDate ?? Date()
            loadProfileSettings(for: user.uid)
            applyInitialSetupState(for: user.uid)
            syncProfileSettingsFromFirestore(userId: user.uid)
            lastObservedAuthUID = user.uid
        } else {
            isSignedIn = false
            userName = ""
            userEmail = ""
            profileImageURL = nil
            requiresInitialSetup = false
            pendingNewSignUpUID = nil
            lastObservedAuthUID = nil

            // Signed-out UI defaults only — per-account values stay in UserDefaults + Firestore.
            userLevel = 1
            registrationDate = Date()
            selectedCategory = .general
        }
    }

    func signIn(email: String, password: String) async throws {
        persistSessionPreferenceForNextLaunch()
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            try await result.user.reload()
            AppAnalytics.shared.log(AppAnalyticsEventName.signInCompleted, params: ["method": "email"])
        } catch {
            AppAnalytics.shared.log(AppAnalyticsEventName.signInFailed, params: [
                "method": "email",
                "error": String(describing: (error as NSError).code)
            ])
            throw error
        }
    }

    func signUp(email: String, password: String, name: String = "") async throws {
        let result: AuthDataResult
        do {
            result = try await Auth.auth().createUser(withEmail: email, password: password)
        } catch {
            AppAnalytics.shared.log(AppAnalyticsEventName.signUpFailed, params: [
                "method": "email",
                "error": String(describing: (error as NSError).code)
            ])
            throw error
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            try await changeRequest.commitChanges()
        }

        pendingNewSignUpUID = result.user.uid
        UserDefaults.standard.set(false, forKey: Self.onboardingCompletedKey(for: result.user.uid))
        applyInitialSetupState(for: result.user.uid)

        registrationDate = Date()
        persistProfileSettings()
        AppAnalytics.shared.log(AppAnalyticsEventName.signUpCompleted, params: ["method": "email"])
    }

    func signInWithGoogle() async throws {
        persistSessionPreferenceForNextLaunch()
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Firebase client ID not found"])
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = await windowScene.windows.first?.rootViewController else {
            throw NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "No root view controller found"])
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "GoogleSignIn", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token"])
        }

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)

        do {
            try await Auth.auth().signIn(with: credential)
            AppAnalytics.shared.log(AppAnalyticsEventName.signInCompleted, params: ["method": "google"])
        } catch {
            AppAnalytics.shared.log(AppAnalyticsEventName.signInFailed, params: [
                "method": "google",
                "error": String(describing: (error as NSError).code)
            ])
            throw error
        }
    }

    func signInWithApple() async throws {
        persistSessionPreferenceForNextLaunch()
        let nonce = Self.randomNonceString()
        currentAppleSignInNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let authorization = try await performAppleAuthorization(request: request)
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw NSError(
                domain: "AppleSignIn",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential."]
            )
        }
        guard let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw NSError(
                domain: "AppleSignIn",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to get Apple identity token."]
            )
        }
        guard let rawNonce = currentAppleSignInNonce else {
            throw NSError(
                domain: "AppleSignIn",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing Apple sign-in nonce."]
            )
        }

        let credential = OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: rawNonce,
            fullName: appleIDCredential.fullName
        )

        do {
            try await Auth.auth().signIn(with: credential)
            AppAnalytics.shared.log(AppAnalyticsEventName.signInCompleted, params: ["method": "apple"])
        } catch {
            AppAnalytics.shared.log(AppAnalyticsEventName.signInFailed, params: [
                "method": "apple",
                "error": String(describing: (error as NSError).code)
            ])
            throw error
        }
    }

    func signOut() throws {
        // Clear local caches before auth becomes nil so managers that listen to auth transitions still start clean.
        Self.clearPerAccountLocalCaches()
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        UserDefaults.standard.set(false, forKey: Self.signOutOnNextLaunchDefaultsKey)
    }

    func setRememberMeEnabled(_ enabled: Bool) {
        rememberMeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.rememberMeDefaultsKey)
    }

    func setSelectedCategory(_ category: VocabularyCategory) {
        selectedCategory = category
        persistProfileSettings()
    }

    func setUserLevel(_ level: Int) {
        userLevel = min(max(level, 1), 11)
        persistProfileSettings()
    }

    func completeInitialSetup(name: String, profileImageData: Data?, level: Int) async throws {
        try await updateDisplayName(name)
        if let profileImageData {
            try await uploadProfilePhoto(imageData: profileImageData)
        }
        setUserLevel(level)

        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedKey(for: uid))
        requiresInitialSetup = false
        pendingNewSignUpUID = nil
    }

    /// DEBUG / TestFlight: test premium behavior without a store subscription.
    func setDebugPremiumOverride(_ value: Bool) {
        guard BuildFeatures.allowsInternalPremiumOverride else { return }
        UserDefaults.standard.set(value, forKey: Self.debugPremiumDefaultsKey)
        publishPremiumState()
    }

    private var debugPremiumOverride: Bool {
        UserDefaults.standard.bool(forKey: Self.debugPremiumDefaultsKey)
    }

    // MARK: - StoreKit

    private func startListeningForSubscriptions() {
        storeKitUpdatesTask?.cancel()
        storeKitUpdatesTask = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshSubscriptionEntitlement()
            }
        }
        Task { await refreshSubscriptionEntitlement() }
    }

    func refreshSubscriptionEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard SubscriptionConfig.premiumProductIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil {
                active = true
                break
            }
        }

        await MainActor.run {
            self.subscriptionEntitlementActive = active
            self.publishPremiumState()
        }
    }

    func purchase(_ product: Product) async throws {
        let planType = SubscriptionConfig.planType(for: product.id)

        AppAnalytics.shared.log(AppAnalyticsEventName.purchaseStarted, params: [
            "product_id": product.id,
            "plan_type": planType
        ])
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            if transaction.offerType == .introductory {
                AppAnalytics.shared.log("trial_started", params: [
                    "product_id": product.id,
                    "plan_type": planType
                ])
            }
            await transaction.finish()
            await refreshSubscriptionEntitlement()
            AppAnalytics.shared.log(AppAnalyticsEventName.purchaseSuccess, params: [
                "product_id": product.id,
                "plan_type": planType
            ])
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async throws {
        AppAnalytics.shared.log(AppAnalyticsEventName.restorePurchaseStarted)
        do {
            try await AppStore.sync()
            await refreshSubscriptionEntitlement()
            AppAnalytics.shared.log(AppAnalyticsEventName.restorePurchaseSuccess)
        } catch {
            AppAnalytics.shared.log(AppAnalyticsEventName.restorePurchaseFailed, params: [
                "error": String(describing: (error as NSError).code)
            ])
            throw error
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    private func publishPremiumState() {
        let overrideActive = BuildFeatures.allowsInternalPremiumOverride && debugPremiumOverride
        let combined = subscriptionEntitlementActive || overrideActive
        if isPremium != combined {
            isPremium = combined
        }
    }

    private static func onboardingCompletedKey(for uid: String) -> String {
        onboardingCompletedPrefix + uid
    }

    private func applyInitialSetupState(for uid: String) {
        let defaults = UserDefaults.standard
        let key = Self.onboardingCompletedKey(for: uid)
        if defaults.object(forKey: key) == nil {
            let isNewSignUp = (pendingNewSignUpUID == uid)
            defaults.set(!isNewSignUp, forKey: key)
        }
        requiresInitialSetup = !defaults.bool(forKey: key)
    }

    func uploadProfilePhoto(imageData: Data) async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "UserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let storage = Storage.storage()
        let ref = storage.reference().child("users").child(user.uid).child("profile.jpg")

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        let downloadURL = try await ref.downloadURL()

        setProfilePhotoHidden(false, uid: user.uid)

        let changeRequest = user.createProfileChangeRequest()
        changeRequest.photoURL = downloadURL
        try await changeRequest.commitChanges()

        profileImageURL = downloadURL.absoluteString
    }

    func removeProfilePhoto() async throws {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "UserManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        let ref = Storage.storage().reference().child("users").child(user.uid).child("profile.jpg")
        try? await ref.delete()

        // Firebase Auth keeps provider photoURL after `nil` (common with Google Sign-In).
        // Persist a per-account opt-out so the UI shows the placeholder immediately.
        setProfilePhotoHidden(true, uid: user.uid)
        profileImageURL = nil
    }

    private static func profilePhotoHiddenKey(for uid: String) -> String {
        profilePhotoHiddenPrefix + uid
    }

    private func isProfilePhotoHidden(uid: String) -> Bool {
        UserDefaults.standard.bool(forKey: Self.profilePhotoHiddenKey(for: uid))
    }

    private func setProfilePhotoHidden(_ hidden: Bool, uid: String) {
        UserDefaults.standard.set(hidden, forKey: Self.profilePhotoHiddenKey(for: uid))
    }

    private func resolvedProfileImageURL(for user: FirebaseAuth.User) -> String? {
        guard !isProfilePhotoHidden(uid: user.uid) else { return nil }
        return user.photoURL?.absoluteString
    }

    func updateDisplayName(_ newName: String) async throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "UserManager",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty"]
            )
        }
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "UserManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Not signed in"]
            )
        }

        let changeRequest = user.createProfileChangeRequest()
        changeRequest.displayName = trimmed
        try await changeRequest.commitChanges()
        userName = trimmed
    }

    private func loadUserData() {
        if let uid = Auth.auth().currentUser?.uid {
            loadProfileSettings(for: uid)
        } else {
            userLevel = 1
            selectedCategory = .general
        }

        if let savedDate = UserDefaults.standard.object(forKey: "registrationDate") as? Date {
            registrationDate = savedDate
        }

        publishPremiumState()
    }

    // MARK: - Profile settings (level + category) — UserDefaults cache + Firestore

    private static func userLevelKey(for uid: String) -> String {
        "userLevel.\(uid)"
    }

    private static func categoryKey(for uid: String) -> String {
        "vocabularyCategory.\(uid)"
    }

    private func profileSettingsRef(userId: String) -> DocumentReference {
        db.collection("users").document(userId).collection("appData").document(Self.profileSettingsDoc)
    }

    private func loadProfileSettings(for uid: String) {
        let defaults = UserDefaults.standard
        let levelKey = Self.userLevelKey(for: uid)
        var level = defaults.integer(forKey: levelKey)
        if level == 0 {
            level = defaults.integer(forKey: Self.legacyUserLevelDefaultsKey)
            if level > 0 {
                defaults.set(level, forKey: levelKey)
                defaults.removeObject(forKey: Self.legacyUserLevelDefaultsKey)
            }
        }
        userLevel = level == 0 ? 1 : min(max(level, 1), 11)

        let categoryKey = Self.categoryKey(for: uid)
        if let raw = defaults.string(forKey: categoryKey),
           let cat = VocabularyCategory(rawValue: raw) {
            selectedCategory = cat
        } else if let legacyRaw = defaults.string(forKey: Self.legacyCategoryDefaultsKey),
                  let cat = VocabularyCategory(rawValue: legacyRaw) {
            selectedCategory = cat
            defaults.set(legacyRaw, forKey: categoryKey)
            defaults.removeObject(forKey: Self.legacyCategoryDefaultsKey)
        }
    }

    private func saveProfileSettingsLocally(for uid: String) {
        let defaults = UserDefaults.standard
        defaults.set(userLevel, forKey: Self.userLevelKey(for: uid))
        defaults.set(selectedCategory.rawValue, forKey: Self.categoryKey(for: uid))
        defaults.set(registrationDate, forKey: "registrationDate")
    }

    private func persistProfileSettings() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        saveProfileSettingsLocally(for: uid)
        saveProfileSettingsToFirestore(userId: uid)
    }

    private func saveProfileSettingsToFirestore(userId: String) {
        profileSettingsRef(userId: userId).setData([
            "userLevel": userLevel,
            "vocabularyCategory": selectedCategory.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ], merge: true) { error in
            if let error = error, (error as NSError).code != 7 {
                print("❌ profileSettings Firestore save error: \(error.localizedDescription)")
            }
        }
    }

    private func syncProfileSettingsFromFirestore(userId: String) {
        profileSettingsRef(userId: userId).getDocument { [weak self] snapshot, error in
            guard let self else { return }
            if let error = error {
                if (error as NSError).code != 7 {
                    print("❌ profileSettings Firestore load error: \(error.localizedDescription)")
                }
                return
            }

            DispatchQueue.main.async {
                guard Auth.auth().currentUser?.uid == userId else { return }

                if snapshot?.exists == true, let data = snapshot?.data() {
                    self.applyProfileSettings(from: data, userId: userId)
                } else {
                    // Existing install: push locally cached level to cloud once.
                    self.saveProfileSettingsToFirestore(userId: userId)
                }
            }
        }
    }

    private func applyProfileSettings(from data: [String: Any], userId: String) {
        if let level = Self.intFromFirestore(data["userLevel"]), (1...11).contains(level) {
            userLevel = level
        }
        if let raw = data["vocabularyCategory"] as? String,
           let category = VocabularyCategory(rawValue: raw) {
            selectedCategory = category
        }
        saveProfileSettingsLocally(for: userId)
    }

    private static func intFromFirestore(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let i = value as? Int { return i }
        if let i64 = value as? Int64 { return Int(i64) }
        if let n = value as? NSNumber { return n.intValue }
        return nil
    }

    private func saveUserData() {
        if let uid = Auth.auth().currentUser?.uid {
            saveProfileSettingsLocally(for: uid)
        }
    }

    private func persistSessionPreferenceForNextLaunch() {
        UserDefaults.standard.set(rememberMeEnabled, forKey: Self.rememberMeDefaultsKey)
        UserDefaults.standard.set(!rememberMeEnabled, forKey: Self.signOutOnNextLaunchDefaultsKey)
    }

    // MARK: - Firebase ID Token (Cloud Run)

    func fetchIDToken(forceRefresh: Bool = false) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "UserManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        return try await withCheckedThrowingContinuation { cont in
            user.getIDTokenForcingRefresh(forceRefresh) { token, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: token ?? "")
                }
            }
        }
    }

    // MARK: - Apple Sign-In helpers

    private func performAppleAuthorization(request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleSignInDelegate(
                onSuccess: { authorization in
                    continuation.resume(returning: authorization)
                },
                onError: { error in
                    continuation.resume(throwing: error)
                }
            )
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            objc_setAssociatedObject(controller, &AppleSignInDelegate.associationKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.performRequests()
        }
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let errorCode = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if errorCode != errSecSuccess {
                fatalError("Unable to generate nonce. OSStatus \(errorCode)")
            }

            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }
}

private final class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    static var associationKey: UInt8 = 0

    private let onSuccess: (ASAuthorization) -> Void
    private let onError: (Error) -> Void

    init(onSuccess: @escaping (ASAuthorization) -> Void, onError: @escaping (Error) -> Void) {
        self.onSuccess = onSuccess
        self.onError = onError
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onSuccess(authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onError(error)
    }
}
