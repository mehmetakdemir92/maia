//
//  MainTabView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var languageManager: AppLanguageManager
    @StateObject private var streakManager = StreakManager()
    @StateObject private var badgeManager = BadgeManager()
    @StateObject private var diaryManager = DiaryManager()
    @StateObject private var statsManager = StatsManager()
    @StateObject private var progressManager = WordProgressManager()
    @StateObject private var quizEventManager = QuizEventManager()
    @State private var showingSettings = false
    
    var body: some View {
        TabView {
            TodayTabView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
            
            DiaryView()
                .tabItem {
                    Label("Diary", systemImage: "book.fill")
                }
            
            StreakView()
                .tabItem {
                    Label("Streak", systemImage: "flame.fill")
                }

            // Collection tab hidden temporarily; CollectionView.swift retained.
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .id(languageManager.refreshID)
        .tint(Color(red: 23/255, green: 22/255, blue: 64/255))
        .environmentObject(userManager)
        .environmentObject(streakManager)
        .environmentObject(badgeManager)
        .environmentObject(diaryManager)
        .environmentObject(statsManager)
        .environmentObject(progressManager)
        .environmentObject(quizEventManager)
        .onAppear {
            if !userManager.isPremium {
                QuizInterstitialAdPresenter.shared.preload()
            }
        }
        .onChange(of: userManager.isPremium) { _, isPremium in
            if !isPremium {
                QuizInterstitialAdPresenter.shared.preload()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(UserManager())
        .environmentObject(AppLanguageManager())
        .environmentObject(StreakManager())
        .environmentObject(BadgeManager())
        .environmentObject(DiaryManager())
        .environmentObject(StatsManager())
        .environmentObject(WordProgressManager())
        .environmentObject(QuizEventManager())
}
