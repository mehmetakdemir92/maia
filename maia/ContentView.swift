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
    }
}

#Preview {
    ContentView()
        .environmentObject(AppLanguageManager())
}

private struct InitialSetupView: View {
    private enum Step {
        case profile
        case level
    }

    private static let cefrMainLevels: [String] = ["A1", "A2", "B1", "B2", "C1", "C2"]

    @EnvironmentObject private var userManager: UserManager
    @State private var step: Step = .profile
    @State private var name: String = ""
    @State private var selectedLevelStep = 1
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
                    if step == .profile {
                        profileStepContent
                            .padding(.top, 44)
                        Spacer()
                    } else {
                        levelStepContent
                        Spacer()
                    }

                    if step == .profile {
                        Button {
                            step = .level
                        } label: {
                            Text("Continue")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.primaryButtonGradient)
                                .cornerRadius(12)
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button {
                            Task {
                                isSaving = true
                                do {
                                    try await userManager.completeInitialSetup(
                                        name: name,
                                        profileImageData: selectedPhotoData,
                                        level: selectedLevelStep
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
                        .disabled(isSaving)
                    }
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

    private var levelStepContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set your English level")
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text("Current level: \(CEFRLevelMapping.label(for: selectedLevelStep))")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.92))

            VStack(spacing: 10) {
                ForEach(Array(CEFRLevelMapping.stepLabels.enumerated()), id: \.offset) { index, level in
                    let stepValue = index + 1
                    Button {
                        selectedLevelStep = stepValue
                    } label: {
                        ZStack {
                            Text(level)
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    selectedLevelStep == stepValue
                                        ? Color.white.opacity(0.34)
                                        : Color.white.opacity(0.14)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(selectedLevelStep == stepValue ? 0.6 : 0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
