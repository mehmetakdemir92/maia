//
//  UserManager.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

class UserManager: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var userName: String = ""
    @Published var userEmail: String = ""
    @Published var profileImageURL: String? = nil
    @Published var followers: Int = 0
    @Published var following: Int = 0
    @Published var isPremium: Bool = false
    @Published var userLevel: Int = 1 // 1-10 scale
    @Published var registrationDate: Date = Date()
    
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    
    init() {
        // Listen to authentication state changes
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.updateUserState(user: user)
            }
        }
        loadUserData()
    }
    
    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    private func updateUserState(user: FirebaseAuth.User?) {
        if let user = user {
            isSignedIn = true
            userEmail = user.email ?? ""
            userName = user.displayName ?? userEmail.components(separatedBy: "@").first ?? "User"
            profileImageURL = user.photoURL?.absoluteString
            registrationDate = user.metadata.creationDate ?? Date()
            saveUserData()
        } else {
            isSignedIn = false
            userName = ""
            userEmail = ""
            profileImageURL = nil
            saveUserData()
        }
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        // updateUserState will be called automatically by authStateDidChangeListener
    }
    
    func signUp(email: String, password: String, name: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        
        // Update user profile with display name
        let changeRequest = result.user.createProfileChangeRequest()
        changeRequest.displayName = name
        try await changeRequest.commitChanges()
        
        // Set registration date
        registrationDate = Date()
        saveUserData()
    }
    
    func signInWithGoogle() async throws {
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
        
        try await Auth.auth().signIn(with: credential)
        // updateUserState will be called automatically by authStateDidChangeListener
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        // updateUserState will be called automatically by authStateDidChangeListener
    }
    
    private func loadUserData() {
        // Load non-auth data from UserDefaults
        isPremium = UserDefaults.standard.bool(forKey: "isPremium")
        userLevel = UserDefaults.standard.integer(forKey: "userLevel")
        if userLevel == 0 { userLevel = 1 }
        
        if let savedDate = UserDefaults.standard.object(forKey: "registrationDate") as? Date {
            registrationDate = savedDate
        }
    }
    
    private func saveUserData() {
        UserDefaults.standard.set(isPremium, forKey: "isPremium")
        UserDefaults.standard.set(userLevel, forKey: "userLevel")
        UserDefaults.standard.set(registrationDate, forKey: "registrationDate")
    }
}
