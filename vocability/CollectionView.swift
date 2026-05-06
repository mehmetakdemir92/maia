//
//  CollectionView.swift
//  vocability
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct CollectionView: View {
    @EnvironmentObject var badgeManager: BadgeManager
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 20) {
                    ForEach(badgeManager.badges) { badge in
                        BadgeCard(badge: badge)
                    }
                }
                .padding()
            }
            .background(AppColors.background)
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct BadgeCard: View {
    let badge: Badge
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? AppColors.primaryButton.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: badge.iconName)
                    .font(.system(size: 40))
                    .foregroundColor(badge.isUnlocked ? AppColors.primaryButton : .gray)
            }
            
            Text(badge.name)
                .font(.headline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Text(badge.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if !badge.isUnlocked {
                Text(badge.requirement)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
            } else {
                Text("Unlocked")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(AppColors.backBlue)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        .opacity(badge.isUnlocked ? 1.0 : 0.6)
    }
}

#Preview {
    CollectionView()
        .environmentObject(BadgeManager())
}
