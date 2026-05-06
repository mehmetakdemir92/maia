//
//  CollectionView.swift
//  maia
//
//  Created by Mehmet Akdemir on 19.01.2026.
//

import SwiftUI

struct CollectionView: View {
    @EnvironmentObject var badgeManager: BadgeManager
    
    var body: some View {
        NavigationView {
            ZStack {
                GlassSceneBackground()
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(badgeManager.badges) { badge in
                            BadgeCard(badge: badge)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Collection")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct BadgeCard: View {
    let badge: Badge
    
    private let cardHeight: CGFloat = 220
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        badge.isUnlocked
                        ? AppColors.badgeUnlockedCircleGradient
                        : AppColors.badgeLockedCircleGradient
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: badge.iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(
                        badge.isUnlocked
                        ? AppColors.badgeUnlockedIconGradient
                        : AppColors.badgeLockedIconGradient
                    )
            }
            
            Text(String(localized: String.LocalizationValue(stringLiteral: badge.name)))
                .font(.headline.weight(.semibold))
                .foregroundColor(badge.isUnlocked ? AppColors.glassCardTitle : AppColors.glassCardMuted.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            
            Text(String(localized: String.LocalizationValue(stringLiteral: badge.description)))
                .font(.caption)
                .foregroundColor(AppColors.glassCardMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            
            if !badge.isUnlocked {
                Text(String(localized: String.LocalizationValue(stringLiteral: badge.requirement)))
                    .font(.caption2)
                    .foregroundColor(AppColors.glassCardMuted.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 4)
            } else {
                Label("Unlocked", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.success)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .wordCardGlassBackground(cornerRadius: 18)
        .opacity(badge.isUnlocked ? 1.0 : 0.78)
    }
}

#Preview {
    CollectionView()
        .environmentObject(BadgeManager())
}
