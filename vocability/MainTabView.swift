//
//  MainTabView.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var userManager = UserManager()
    @StateObject private var streakManager = StreakManager()
    @StateObject private var badgeManager = BadgeManager()
    @StateObject private var diaryManager = DiaryManager()
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
            
            CollectionView()
                .tabItem {
                    Label("Collection", systemImage: "star.fill")
                }
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
        .environmentObject(userManager)
        .environmentObject(streakManager)
        .environmentObject(badgeManager)
        .environmentObject(diaryManager)
    }
}

#Preview {
    MainTabView()
}
