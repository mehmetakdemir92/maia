//
//  ContentView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI
import PhotosUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var languageManager: AppLanguageManager
    @StateObject private var userManager = UserManager()
    @StateObject private var updateChecker = AppUpdateChecker()

    var body: some View {
        Group {
            if userManager.isSignedIn {
                if userManager.requiresInitialSetup {
                    InitialSetupView()
                        .environmentObject(userManager)
                } else {
                    MainTabView()
                        .environmentObject(userManager)
                }
            } else {
                AuthEntryView()
                    .environmentObject(userManager)
            }
        }
        .id("\(userManager.isSignedIn)-\(languageManager.refreshID)")
        .task {
            await updateChecker.checkOnLaunch()
        }
        .alert("Update Available", isPresented: $updateChecker.updateAvailable) {
            Button("Update Now") {
                AppUpdateChecker.openAppStore()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("A new version of Maia is available with new daily words and improvements.")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppLanguageManager())
}

private struct InitialSetupView: View {
    @EnvironmentObject private var userManager: UserManager
    @State private var name: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            ZStack {
                GlassSceneBackground()

                VStack(alignment: .leading, spacing: 18) {
                    profileStepContent
                        .padding(.top, 44)
                    Spacer()

                    Button {
                        Task {
                            isSaving = true
                            do {
                                try await userManager.completeInitialSetup(
                                    name: name,
                                    profileImageData: selectedPhotoData
                                )
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                            isSaving = false
                        }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().progressViewStyle(.circular)
                            }
                            Text("Continue")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.primaryButtonGradient)
                        .cornerRadius(12)
                    }
                    .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
            }
            .navigationBarBackButtonHidden(true)
            .alert("Setup error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
        }
    }

    private var profileStepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Complete your profile")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)

                Text("Set your name.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.88))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 60)

            HStack {
                Spacer()
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 110, height: 110)
                            if let selectedPhotoData,
                               let image = UIImage(data: selectedPhotoData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 110, height: 110)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 52, height: 52)
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }

                        Text("Choose Photo")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.35), in: Capsule())
                    }
                }
                Spacer()
            }
            .padding(.top, 18)

            TextField(
                "",
                text: $name,
                prompt: Text("Name Surname")
                    .foregroundColor(AppColors.glassCardMuted)
            )
                .textInputAutocapitalization(.words)
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
                .padding(.top, 30)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let jpegData = image.jpegData(compressionQuality: 0.75) {
                        selectedPhotoData = jpegData
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

}
